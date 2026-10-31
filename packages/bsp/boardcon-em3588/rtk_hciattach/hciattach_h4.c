// SPDX-License-Identifier: GPL-2.0
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>
#include <termios.h>
#include <time.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/param.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <endian.h>
#include <byteswap.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/timerfd.h>
#include <sys/epoll.h>
#include "hciattach.h"
#include "hciattach_h4.h"
#include "rtb_fwc.h"

extern struct rtb_struct rtb_cfg;

static uint32_t get_unaligned_be32(const void *mem)
{
	const uint8_t *p = mem;

	return p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3];
}

static uint32_t get_unaligned_le16(const void *mem)
{
	const uint8_t *p = mem;

	return p[1] << 8 | p[0];
}

static int read_data(int fd, uint8_t *buf, size_t len)
{
	size_t t = 0;
	ssize_t w = 0;
#define NUM_OF_RETRY	10
	int count = 0;

	if (fd < 0 || !buf || !len)
		return -EINVAL;

	while (len > 0) {
		if ((w = read(fd, buf, len)) < 0) {
			if (errno == EINTR || errno == EAGAIN)
				continue;
			return -1;
		}
		if (!w && ++count > NUM_OF_RETRY)
			return 0;
		len -= w;
		buf += w;
		t += w;
	}
	return t;
}

static int start_xfer_wait(int fd, uint8_t *cmd, uint16_t len, uint32_t msec,
			   int retry, uint8_t *resp, uint16_t *resp_len)
{
	uint8_t buf[64];
	int result;
	int state = 1;
	int count = 0;
	int params_len;
	struct pollfd p[2];
	uint16_t opcode;

	if (fd == -1 || !cmd || len < 4) {
		RS_ERR("%s: invalid parameter", __func__);
		return -1;
	}

	opcode = ((uint16_t)cmd[2] << 8) + cmd[1];

start_xfer:
	result = write(fd, cmd, len);
	if (result != len) {
		RS_ERR("%s: Write cmd %04x error, %s", __func__, opcode,
		       strerror(errno));
		return -1;
	}

start_recv:
	memset(buf, 0, sizeof(buf));
	memset(p, 0, sizeof(p));
	state = 1;
	count = 0;
	p[0].fd = fd;
	p[0].events = POLLERR | POLLHUP | POLLIN;
	for (;;) {
		p[0].revents = 0;
		result = poll(p, 1, msec);
		if (result < 0) {
			RS_ERR("Poll call error, %s", strerror(errno));
			result = -1;
			break;
		}

		if (result == 0) {
			RS_WARN("%s: Timeout", __func__);
			util_hexdump(cmd, len);
			if (retry <= 0) {
				RS_ERR("%s: Transfer exhausted", __func__);
				tcflush(fd, TCIOFLUSH);
				exit(EXIT_FAILURE);
			}
			retry--;
			goto start_xfer;
		}

		if (p[0].revents & (POLLERR | POLLHUP)) {
			RS_ERR("POLLERR or POLLUP happens, %s",
			       strerror(errno));
			result = -1;
			break;
		}

		if (state == 1) {
			result = read_data(p[0].fd, buf, 1);
			if (result == -1 || result != 1) {
				RS_ERR("%s: Read pkt type error, %s", __func__,
				       strerror(errno));
				result = -1;
				break;
			}
			if (result == 1 && buf[0] == 0x04) {
				count = 1;
				state = 2;
			}
		} else if (state == 2) {
			result = read_data(p[0].fd, buf + count, 2);
			if (result == -1 || result != 2) {
				RS_ERR("%s: Read pkt header error, %s",
				       __func__, strerror(errno));
				break;
			}
			count += result;
			state = 3;
			params_len = buf[2];
			if (params_len + 3 > sizeof(buf)) {
				result = -1;
				RS_ERR("%s: hci event too long", __func__);
				break;
			}
		} else if (state == 3) {
			result = read(p[0].fd, buf + count, params_len);
			if (result == -1) {
				RS_ERR("%s: Read pkt payload error, %s",
				       __func__, strerror(errno));
				break;
			}
			count += result;
			params_len -= result;
			if (!params_len)
				break;
		}
	}

	if (result >= 0) {
		struct hci_cc_common *cc = (void *)(buf + 1);

		if (cc->evt_code == 0x0e) {
			uint16_t tmp_opcode;

			tmp_opcode = (uint16_t)buf[4] | buf[5] << 8;
			if (tmp_opcode == opcode) {
				/* RS_INFO("Cmd complete event for cmd %04x",
				 * 	opcode);
				 */
				/* Status is not zero indicating command not
				 * succeeded */
				if (cc->status) {
					RS_ERR("cc status 0x%02x", cc->status);
					return -1;
				}
				if (!resp)
					return 0;
				if (*resp_len > count)
					*resp_len = count;
				memcpy(resp, buf, *resp_len);
				return 0;
			} else {
				RS_WARN("Unexpected cmd complete event, %04x",
					tmp_opcode);
				return -1;
			}
		} else {
			RS_INFO("%s: Unexpected hci event packet", __func__);
			util_hexdump(buf, count);
			/* Continue receiving */
		}
		goto start_recv;
	}

	return result;
}

int h4_download_patch(int fd, int index, uint8_t *data, int len)
{
	uint8_t buf[257];
	uint16_t total_len;
	int result;
	uint8_t resp[8];
	uint16_t rlen = sizeof(resp);

	/* RS_DBG("fd: %d, index: %d, len: %d", fd, index, len); */

	if (data)
		memcpy(&buf[5], data, len);
	buf[0] = 0x01;
	buf[1] = 0x20;
	buf[2] = 0xfc;
	buf[3] = len + 1;
	buf[4] = (uint8_t)index;
	total_len = len + 5;

	result = start_xfer_wait(fd, buf, total_len, 1000, 0, resp, &rlen);
	if (result < 0) {
		RS_ERR("Transfer patch failed, index %d", index);
		return -1;
	}

	if (rlen != 8) {
		RS_ERR("%s: Unexpected length %u", __func__, rlen);
		return -1;
	}

	return resp[7];
}

int h4_vendor_change_speed(int fd, uint32_t baudrate)
{
	int res;
	uint8_t cmd[8] = { 0 };

	cmd[0] = 1;
	cmd[1] = 0x17;
	cmd[2] = 0xfc;
	cmd[3] = 4;

	baudrate = cpu_to_le32(baudrate);
#ifdef BAUDRATE_4BYTES
	memcpy((uint16_t *) & cmd[4], &baudrate, 4);
#else
	memcpy((uint16_t *) & cmd[4], &baudrate, 2);
	cmd[6] = 0;
	cmd[7] = 0;
#endif

	/* TODO: Wait for a while for device to up, just h4 need it */
	sleep(1);

	RS_DBG("baudrate in change speed command: 0x%02x 0x%02x 0x%02x 0x%02x",
	       cmd[4], cmd[5], cmd[6], cmd[7]);

	res = start_xfer_wait(fd, cmd, 8, 1000, 0, NULL, 0);
	if (res < 0)
		RS_ERR("Change Controller baud failed");

	return res;
}

int h4_hci_reset(int fd)
{
	int result;
	uint8_t cmd[4] = { 0x01, 0x03, 0x0c, 0x00};

	RS_INFO("%s: Issue hci reset cmd", __func__);

	result = start_xfer_wait(fd, cmd, sizeof(cmd), 1000, 0, NULL, 0);
	if (result < 0) {
		RS_ERR("%s: Failed to send reset cmd", __func__);
		return -1;
	}

	return 0;
}

int h4_read_local_ver(int fd)
{
	uint8_t cmd[4] = { 0x01, 0x01, 0x10, 0x00 };
	uint8_t resp[16];
	uint16_t len = sizeof(resp);
	int result;

	result = start_xfer_wait(fd, cmd, sizeof(cmd), 1000, 0,
				 resp, &len);
	if (result < 0) {
		RS_ERR("HCI Read local version info error");
		return -1;
	}

	if (len != 15) {
		RS_ERR("%s: Unexpected length %u", __func__, len);
		return -1;
	}
	rtb_cfg.hci_ver = resp[7];
	rtb_cfg.hci_rev = (uint32_t)resp[9] << 8 | resp[8];
	rtb_cfg.lmp_subver = (uint32_t)resp[14] << 8 | resp[13];
	RS_INFO("hci ver %02x, hci_rev %04x, lmp_subver %04x",
		rtb_cfg.hci_ver, rtb_cfg.hci_rev, rtb_cfg.lmp_subver);
	return 0;
}

int h4_vendor_read_rom_ver(int fd)
{
	uint8_t cmd[4] = { 0x01, 0x6d, 0xfc, 0x00 };
	uint8_t resp[16];
	uint16_t len = sizeof(resp);
	int result;

	result = start_xfer_wait(fd, cmd, sizeof(cmd), 1000, 0,
				 resp, &len);
	if (result < 0) {
		RS_ERR("HCI Read local version info error");
		return -1;
	}

	if (len != 8) {
		RS_ERR("%s: Unexpected length %u", __func__, len);
		return -1;
	}
	rtb_cfg.eversion = resp[7];
	RS_INFO("eversion %02x", rtb_cfg.eversion);
	return 0;
}

uint8_t *h4_vendor_cmd(int fd, uint16_t opcode, uint8_t subopcode,
		       uint8_t plen, uint8_t *param, uint32_t to)
{
	uint8_t *rsp = NULL;
	uint8_t *cmd = NULL;
	struct hci_cmd_hdr *hdr;
	struct hci_cc_common *cc;
	int result;
	uint16_t len;
	uint8_t *p;

	cmd = malloc(MAX_HCI_COMMAND_SIZE);
	if (!cmd)
		return NULL;
	rsp = malloc(MAX_HCI_EVENT_SIZE);
	if (!rsp)
		goto err;
	p = cmd;
	*p = 0x01;
	p++;
	hdr = (void *)p;
	p += sizeof(*hdr);
	hdr->opcode[0] = opcode & 0xff;
	hdr->opcode[1] = (opcode >> 8) & 0xff;
	if (subopcode != SUBOPCODE_NONE) {
		*p++ = subopcode;
		hdr->plen = plen + 1;
	} else {
		hdr->plen = plen;
	}
	if (plen) {
		memcpy(p, param, plen);
		p += plen;
	}

	RS_INFO("%s: cmd %08x-%08x-%08x", __func__, get_unaligned_be32(cmd),
		get_unaligned_be32(cmd + 4),
		get_unaligned_be32(cmd + 8));

	len = MAX_HCI_EVENT_SIZE;
	result = start_xfer_wait(fd, cmd, p - cmd, to, 0, rsp, &len);
	if (result < 0) {
		RS_ERR("hci send vendor cmd %04x err", opcode);
		goto err;
	}

	if (len < 1 + sizeof(*cc)) {
		RS_ERR("%s: Unexpected length %u", __func__, len);
		goto err;
	}

	p = rsp;
	p++;
	cc = (void *)rsp;
	p += sizeof(*cc);
	p += cc->plen;

	if (p - rsp > MAX_HCI_EVENT_SIZE) {
		RS_ERR("%s: invalid cc payload, %08x-%08x-%08x-%08x", __func__,
			get_unaligned_be32(rsp),
			get_unaligned_be32(rsp + 4),
			get_unaligned_be32(rsp + 8),
			get_unaligned_be32(rsp + 12));
		goto err;
	}

	free(cmd);

	/* FIXME: Callers must free the rsp */
	return rsp;
err:
	if (cmd)
		free(cmd);
	if (rsp)
		free(rsp);
	return NULL;
}

int h4_needs_hci_upgrade(int fd, uint8_t *buf, uint32_t len)
{
	uint8_t *rsp = NULL;
	uint8_t *mem = NULL;
	uint8_t plen = UPG_DL_BLOCK_SIZE;
	struct hci_cc_common *cc;
	struct {
		uint8_t subopcode;
		uint8_t upgrade;
	} __attribute__((packed)) *cc_trail;
	int ret = -1;
	uint8_t upgrade;

	if (len < plen)
		plen = len;
	rsp = h4_vendor_cmd(fd, 0xfdbb, SUBOPCODE_CKUPG, plen, buf, 1000);
	if (!rsp) {
		ret = -2;
		goto err;
	}

	mem = rsp;
	rsp++;
	cc = (void *)rsp;
	if (cc->status) {
		RS_ERR("Status 0x%02x err", cc->status);
		ret = -3;
		goto err;
	}
	cc_trail = (void *)(rsp + sizeof(*cc));
	if (cc_trail->subopcode != SUBOPCODE_CKUPG) {
		RS_ERR("subopcode (%u-%u) mismatch", cc_trail->subopcode,
		       SUBOPCODE_CKUPG);
		ret = -4;
		goto err;
	}

	upgrade = cc_trail->upgrade;
	free(mem);
	return upgrade;

err:
	if (mem)
		free(mem);
	return ret;
}

int h4_enable_gen_iso_num_compl_pkt_evt(int fd)
{
	uint8_t *rsp = NULL;
	uint8_t *mem = NULL;
	struct hci_cc_common *cc;
	int ret = -1;
	uint8_t pdu[3] = { 0x0b, 0x09, 0x01 };

	rsp = h4_vendor_cmd(fd, 0xfdbd, SUBOPCODE_NONE, sizeof(pdu), pdu, 1000);
	if (!rsp) {
		ret = -2;
		goto err;
	}

	mem = rsp;
	rsp++;
	cc = (void *)rsp;
	if (cc->status) {
		RS_ERR("Status 0x%02x err of cmd %04x", cc->status,
		       get_unaligned_le16(cc->opcode));
		ret = -3;
		goto err;
	}

	free(mem);

	RS_INFO("Succeed in enabling gen iso num of completed pkt evt");

	return 0;

err:
	if (mem)
		free(mem);
	return ret;
}
