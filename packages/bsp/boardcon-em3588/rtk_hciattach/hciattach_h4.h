// SPDX-License-Identifier: GPL-2.0
#include <stdint.h>

int h4_download_patch(int fd, int index, uint8_t *data, int len);
int h4_vendor_change_speed(int fd, uint32_t baudrate);
int h4_hci_reset(int fd);
int h4_read_local_ver(int fd);
int h4_vendor_read_rom_ver(int fd);
uint8_t *h4_vendor_cmd(int fd, uint16_t opcode, uint8_t subopcode,
		       uint8_t plen, uint8_t *param, uint32_t to);
int h4_needs_hci_upgrade(int fd, uint8_t *buf, uint32_t len);
int h4_enable_gen_iso_num_compl_pkt_evt(int fd);
