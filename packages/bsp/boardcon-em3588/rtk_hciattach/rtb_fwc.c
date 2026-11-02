/*
 *  Copyright (C) 2018 Realtek Semiconductor Corporation.
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <ctype.h>

#ifndef PATH_MAX
#define PATH_MAX	1024
#endif

#include "hciattach.h"
#include "rtb_fwc.h"

#define ARRAY_SIZE(a)	(sizeof(a) / sizeof(a[0]))

#define FIRMWARE_DIRECTORY	"/lib/firmware/rtlbt/"
#define BT_CONFIG_DIRECTORY	"/lib/firmware/rtlbt/"
#define EXTRA_CONFIG_FILE	"/opt/rtk_btconfig.txt"
#define BT_ADDR_FILE		"/opt/bdaddr"
#define BDADDR_STRING_LEN	17

struct list_head {
	struct list_head *next, *prev;
};

struct cfg_list_item {
	struct list_head list;
	uint16_t offset;
	uint8_t len;
	uint8_t data[0];
};

const uint8_t cfg_magic[4] = { 0x55, 0xab, 0x23, 0x87 };
static struct list_head list_configs;
static struct list_head list_extracfgs;

struct rtb_cfg_item {
	uint16_t offset;
	uint8_t len;
	uint8_t data[0];
} __attribute__ ((packed));

struct rtk_bt_vendor_config {
        uint32_t signature;
        uint16_t data_len;
        struct rtb_cfg_item entry[0];
} __attribute__ ((packed));

#define RTB_CFG_HDR_LEN		6

struct rtb_patch_entry {
	uint16_t chip_id;
	uint16_t patch_len;
	uint32_t soffset;
	uint32_t svn_ver;
	uint32_t coex_ver;
} __attribute__ ((packed));

struct rtb_patch_hdr {
	uint8_t signature[8];
	uint32_t fw_version;
	uint16_t number_of_patch;
	struct rtb_patch_entry entry[0];
} __attribute__ ((packed));

#define PATCH_SNIPPETS		0x01
#define PATCH_DUMMY_HEADER	0x02
#define PATCH_SECURITY_HEADER	0x03
#define PATCH_OTA_FLAG		0x04
#define SECTION_HEADER_SIZE	8

struct rtk_eversion_evt {
	uint8_t status;
	uint8_t version;
} __attribute__ ((packed));

struct rtk_epatch_entry {
	uint16_t chipID;
	uint16_t patch_length;
	uint32_t start_offset;
} __attribute__ ((packed));

struct rtk_epatch {
	uint8_t signature[8];
	uint32_t fw_version;
	uint16_t number_of_total_patch;
	struct rtk_epatch_entry entry[0];
} __attribute__ ((packed));

struct rtk_extension_entry {
	uint8_t opcode;
	uint8_t length;
	uint8_t *data;
} __attribute__ ((packed));

struct rtb_section_hdr {
	uint32_t opcode;
	uint32_t section_len;
	uint32_t soffset;
} __attribute__ ((packed));

struct rtb_new_patch_hdr {
	uint8_t signature[8];
	uint8_t fw_version[8];
	uint32_t number_of_section;
} __attribute__ ((packed));

//signature: Realtech
const uint8_t RTK_EPATCH_SIGNATURE[8] =
    { 0x52, 0x65, 0x61, 0x6C, 0x74, 0x65, 0x63, 0x68 };

//signature: RTBTCore
const uint8_t RTK_EPATCH_SIGNATURE_NEW[8] =
    { 0x52, 0x54, 0x42, 0x54, 0x43, 0x6F, 0x72, 0x65 };

//Extension Section IGNATURE:0x77FD0451
const uint8_t Extension_Section_SIGNATURE[4] = { 0x51, 0x04, 0xFD, 0x77 };

static const struct {
	uint16_t lmp_subver;
	uint8_t id;
} project_id_to_lmp_subver[] = {
	{ ROM_LMP_8723a, 0 },
	{ ROM_LMP_8723b, 1 }, /* RTL8723BS */
	{ ROM_LMP_8821a, 2 }, /* RTL8821AS */
	{ ROM_LMP_8761a, 3 }, /* RTL8761ATV */
	{ ROM_LMP_8723c, 7 }, /* index 7 for 8723CS. What is for other 8723CS */
	{ ROM_LMP_8822b, 8 }, /* RTL8822BS */
	{ ROM_LMP_8723b, 9 }, /* RTL8723DS */
	{ ROM_LMP_8821a, 10 }, /* id 10 for RTL8821CS, lmp subver 0x8821 */
	{ ROM_LMP_8822c, 13 }, /* id 13 for RTL8822CS, lmp subver 0x8822 */
	{ ROM_LMP_8761a, 14 }, /* id 14 for 8761B */
	{ ROM_LMP_8852a, 18 }, /* id 18 for 8852AS */
	{ ROM_LMP_8723b, 19 }, /* id 19 for 8733BS */
	{ ROM_LMP_8852a, 20 }, /* id 20 for 8852BS */
	{ ROM_LMP_8852a, 25 }, /* id 25 for 8852CS */
	{ ROM_LMP_8822b, 33 }, /* id 33 for 8822E */
	{ ROM_LMP_8852a, 34 }, /* id 34 for 8852BP */
	{ ROM_LMP_8851b, 36 }, /* id 36 for 8851BS */
	{ ROM_LMP_8852a, 42 }, /* id 42 for 8852DS */
	{ ROM_LMP_8922a, 44 }, /* id 44 for 8922AS */
	{ ROM_LMP_8852a, 47 }, /* id 47 for 8852BTS */
	{ ROM_LMP_8761a, 51 }, /* id 51 for 8761C */
};

static struct patch_info h4_patch_table[] = {
	/* match flags, chip type, lmp subver, proj id(unused), hci_ver,
	 * hci_rev, ...
	 */

	/* RTL8761AT */
	{ RTL_FW_MATCH_CHIP_TYPE, CHIP_8761AT,
		0x8761, 0xffff, 0, 0x000a,
		"rtl8761at_fw", "rtl8761at_config", "RTL8761AT" },
	/* RTL8761ATF */
	{ RTL_FW_MATCH_CHIP_TYPE, CHIP_8761ATF,
		0x8761, 0xffff, 0, 0x000a,
		"rtl8761atf_fw", "rtl8761atf_config", "RTL8761ATF" },
	/* RTL8761B(8763) H4 Test Chip without download
	 * FW/Config is not used.
	 */
	{ RTL_FW_MATCH_CHIP_TYPE, CHIP_8761BTC,
		0x8763, 0xffff, 0, 0x000b,
		"rtl8761btc_fw", "rtl8761btc_config", "RTL8761BTC" },
	/* RTL8761B H4 Test Chip wihtout download*/
	{ RTL_FW_MATCH_CHIP_TYPE, CHIP_8761BH4,
		0x8761, 0xffff, 0, 0x000b,
		"rtl8761bh4_fw", "rtl8761bh4_config", "RTL8761BH4" },

	/* RTL8723DS */
	{ RTL_FW_MATCH_HCI_VER | RTL_FW_MATCH_HCI_REV, CHIP_8723DS,
		ROM_LMP_8723b, ROM_LMP_8723b, 8, 0x000d,
		"rtl8723dsh4_fw", "rtl8723dsh4_config", "RTL8723DSH4"},
	/* RTL8761C */
	{ RTL_FW_MATCH_HCI_REV, CHIP_8761CTV,
		ROM_LMP_8761a, 0xffff, 0x0c, 0x000e,
		"rtl8761c_mx_fw", "rtl8761c_mx_config", "RTL8761CTV" },

	{ 0, 0, 0, ROM_LMP_NONE, 0, 0, "rtl_none_fw", "rtl_none_config", "NONE"}
};

static struct patch_info patch_table[] = {
	/* match flags, chip type, lmp subver, proj id(unused), hci_ver,
	 * hci_rev, ...
	 */

	/* RTL8723AS */
	{ 0, 0, ROM_LMP_8723a, ROM_LMP_8723a, 0, 0,
		"rtl8723a_fw", "rtl8723a_config", "RTL8723AS"},
	/* RTL8821CS */
	{ RTL_FW_MATCH_HCI_REV, CHIP_8821CS,
		ROM_LMP_8821a, ROM_LMP_8821a, 0, 0x000c,
		"rtl8821c_fw", "rtl8821c_config", "RTL8821CS"},
	/* RTL8821AS */
	{ 0, 0, ROM_LMP_8821a, ROM_LMP_8821a, 0, 0,
		"rtl8821a_fw", "rtl8821a_config", "RTL8821AS"},
	/* RTL8761ATV */
	{ RTL_FW_MATCH_HCI_VER | RTL_FW_MATCH_HCI_REV, 0,
		ROM_LMP_8761a, ROM_LMP_8761a, 0x06, 0x000a,
		"rtl8761a_fw", "rtl8761a_config", "RTL8761ATV"},
	/* RTL8725AS */
	{ RTL_FW_MATCH_CHIP_TYPE | RTL_FW_MATCH_HCI_VER | RTL_FW_MATCH_HCI_REV,
		CHIP_8725AS,
		ROM_LMP_8761a, ROM_LMP_8761a, 0x0a, 0x000b,
		"rtl8725as_fw", "rtl8725as_config", "RTL8725AS"},
	/* RTL8761BTV */
	{ RTL_FW_MATCH_HCI_VER | RTL_FW_MATCH_HCI_REV, CHIP_8761B,
		ROM_LMP_8761a, ROM_LMP_8761a, 0x0a, 0x000b,
		"rtl8761b_fw", "rtl8761b_config", "RTL8761BTV"},

	/* RTL8703AS
	 * RTL8822BS
	 * */
#ifdef RTL_8703A_SUPPORT
	{ RTL_FW_MATCH_CHIP_TYPE, CHIP_8703AS,
		ROM_LMP_8723b, ROM_LMP_8723b, 0, 0,
		"rtl8703a_fw", "rtl8703a_config", "RTL8703AS"},
#endif
	{ RTL_FW_MATCH_HCI_REV, CHIP_8822BS,
		ROM_LMP_8822b, ROM_LMP_8822b, 0, 0x000b,
		"rtl8822b_fw", "rtl8822b_config", "RTL8822BS"},
	{ RTL_FW_MATCH_HCI_REV, CHIP_8822CS,
		ROM_LMP_8822c, ROM_LMP_8822c, 0, 0x000c,
		"rtl8822cs_fw", "rtl8822cs_config", "RTL8822CS"},
	/* RTL8822ES */
	{ RTL_FW_MATCH_HCI_VER | RTL_FW_MATCH_HCI_REV, CHIP_8822ES,
		ROM_LMP_8822e, ROM_LMP_8822e, 0, 0x000e,
		"rtl8822es_fw", "rtl8822es_config", "RTL8822ES"},

	/* RTL8852AS */
	{ RTL_FW_MATCH_HCI_REV, CHIP_8852AS,
		ROM_LMP_8852a, ROM_LMP_8852a, 11, 0x000a,
		"rtl8852as_fw", "rtl8852as_config", "RTL8852AS" },

	/* RTL8852BS */
	{ RTL_FW_MATCH_CHIP_TYPE | RTL_FW_MATCH_HCI_VER | RTL_FW_MATCH_HCI_REV, CHIP_8852BS,
		ROM_LMP_8852a, ROM_LMP_8852a, 11, 0x000b,
		"rtl8852bs_fw", "rtl8852bs_config", "RTL8852BS" },

	/* RTL8852BP */
	{ RTL_FW_MATCH_CHIP_TYPE | RTL_FW_MATCH_HCI_VER | RTL_FW_MATCH_HCI_REV, CHIP_8852BP,
		ROM_LMP_8852a, ROM_LMP_8852a, 11, 0x000b,
		"rtl8852bps_fw", "rtl8852bps_config", "RTL8852BP" },

	/* RTL8852CS */
	{ RTL_FW_MATCH_HCI_REV, CHIP_8852CS,
		ROM_LMP_8852a, ROM_LMP_8852a, 11, 0x000c,
		"rtl8852cs_fw", "rtl8852cs_config", "RTL8852CS" },

	/* RTL8851BS */
	{ RTL_FW_MATCH_HCI_REV, CHIP_8851BS,
		ROM_LMP_8851b, ROM_LMP_8851b, 0x0c, 0x000b,
		"rtl8851bs_fw", "rtl8851bs_config", "RTL8851BS" },

	/* RTL8852DS */
	{ RTL_FW_MATCH_HCI_REV, CHIP_8852DS,
		ROM_LMP_8852a, ROM_LMP_8852a, 0x0c, 0x000d,
		"rtl8852ds_fw", "rtl8852ds_config", "RTL8852DS" },

	/* RTL8922AS */
	{ RTL_FW_MATCH_HCI_REV, CHIP_8922AS,
		ROM_LMP_8922a, ROM_LMP_8922a, 0x0c, 0x000a,
		"rtl8922as_fw", "rtl8922as_config", "RTL8922AS" },

	/* RTL8852BTS */
	{ RTL_FW_MATCH_HCI_REV, CHIP_8852BTS,
		ROM_LMP_8852a, ROM_LMP_8852a, 0x0c, 0x0087,
		"rtl8852bts_fw", "rtl8852bts_config", "RTL8852BTS" },

	/* RTL8703BS
	 * RTL8723CS_XX
	 * RTL8723CS_CG
	 * RTL8723CS_VF
	 * Use the sampe lmp subversion 0x8703
	 * */
	{ RTL_FW_MATCH_CHIP_TYPE | RTL_FW_MATCH_HCI_VER | RTL_FW_MATCH_HCI_REV,
		/* The real chip type will be read during init. */
		CHIP_8723CS,
		ROM_LMP_8703b, ROM_LMP_8703b, 7, 0x000b,
		"rtl8723cs_0_fw", "rtl8723cs_0_config", "RTL8723CS"},
	{ RTL_FW_MATCH_CHIP_TYPE, CHIP_8703BS,
		ROM_LMP_8703b, ROM_LMP_8703b, 0, 0,
		"rtl8703b_fw", "rtl8703b_config", "RTL8703BS"},
	{ RTL_FW_MATCH_CHIP_TYPE, CHIP_8723CS_XX,
		ROM_LMP_8703b, ROM_LMP_8723cs_xx, 0, 0,
		"rtl8723cs_fw", "rtl8723cs_config", "RTL8723CS_XX"},
	{ RTL_FW_MATCH_CHIP_TYPE, CHIP_8723CS_CG,
		ROM_LMP_8703b, ROM_LMP_8723cs_cg, 0, 0,
		"rtl8723cs_fw", "rtl8723cs_config", "RTL8723CS_CG"},
	{ RTL_FW_MATCH_CHIP_TYPE, CHIP_8723CS_VF,
		ROM_LMP_8703b, ROM_LMP_8723cs_vf, 0, 0,
		"rtl8723cs_fw", "rtl8723cs_config", "RTL8723CS_VF"},

	/* RTL8723BS */
	{ RTL_FW_MATCH_HCI_VER | RTL_FW_MATCH_HCI_REV, 0,
		ROM_LMP_8723b, ROM_LMP_8723b, 6, 0x000b,
		"rtl8723b_fw", "rtl8723b_config", "RTL8723BS"},
	/* RTL8723DS */
	{ RTL_FW_MATCH_HCI_VER | RTL_FW_MATCH_HCI_REV, CHIP_8723DS,
		ROM_LMP_8723b, ROM_LMP_8723b, 8, 0x000d,
		"rtl8723d_fw", "rtl8723d_config", "RTL8723DS"},
	/* RTL8733BS */
	{ RTL_FW_MATCH_HCI_REV, CHIP_8733BS,
		ROM_LMP_8723b, ROM_LMP_8723b, 0, 0x000f,
		"rtl8733bs_fw", "rtl8733bs_config", "RTL8733BS"},
	/* RTL8761C */
	{ RTL_FW_MATCH_HCI_REV, CHIP_8761CTV,
		ROM_LMP_8761a, 0xffff, 0x0c, 0x000e,
		"rtl8761c_mx_fw", "rtl8761c_mx_config", "RTL8761CTV" },
	/* add entries here*/

	{ 0, 0, 0, ROM_LMP_NONE, 0, 0, "rtl_none_fw", "rtl_none_config", "NONE"}
};

extern int rtb_vendor_read(int dd, uint16_t subopcode);

static __inline uint16_t get_unaligned_le16(uint8_t * p)
{
	return (uint16_t) (*p) + ((uint16_t) (*(p + 1)) << 8);
}

static __inline uint32_t get_unaligned_le32(uint8_t * p)
{
	return (uint32_t) (*p) + ((uint32_t) (*(p + 1)) << 8) +
	    ((uint32_t) (*(p + 2)) << 16) + ((uint32_t) (*(p + 3)) << 24);
}

/* list head from kernel */
#define offsetof(TYPE, MEMBER)	((size_t)&((TYPE *)0)->MEMBER)

#define container_of(ptr, type, member) ({                      \
	const typeof( ((type *)0)->member ) *__mptr = (ptr);    \
	(type *)( (char *)__mptr - offsetof(type,member) );})

#define list_entry(ptr, type, member) \
	container_of(ptr, type, member)

#define list_for_each_safe(pos, n, head) \
	for (pos = (head)->next, n = pos->next; pos != (head); \
		pos = n, n = pos->next)

static inline void INIT_LIST_HEAD(struct list_head *list)
{
	list->next = list;
	list->prev = list;
}

static inline int list_empty(const struct list_head *head)
{
	return head->next == head;
}

static inline void __list_add(struct list_head *_new,
			      struct list_head *prev,
			      struct list_head *next)
{
	next->prev = _new;
	_new->next = next;
	_new->prev = prev;
	prev->next = _new;
}

static inline void list_add_tail(struct list_head *_new, struct list_head *head)
{
	__list_add(_new, head->prev, head);
}

static inline void __list_del(struct list_head *prev, struct list_head *next)
{
	next->prev = prev;
	prev->next = next;
}

static inline bool __list_del_entry_valid(struct list_head *entry)
{
	return true;
}

static inline void __list_del_entry(struct list_head *entry)
{
	if (!__list_del_entry_valid(entry))
		return;

	__list_del(entry->prev, entry->next);
}

static inline void list_del_init(struct list_head *entry)
{
	__list_del_entry(entry);
	INIT_LIST_HEAD(entry);
}

#define LIST_POISON1  ((void *) 0x00100100)
#define LIST_POISON2  ((void *) 0x00200200)
static inline void list_del(struct list_head *entry)
{
	__list_del(entry->prev, entry->next);
	entry->next = (struct list_head*)LIST_POISON1;
	entry->prev = (struct list_head*)LIST_POISON2;
}

static inline void __list_splice(const struct list_head *list,
				 struct list_head *prev,
				 struct list_head *next)
{
	struct list_head *first = list->next;
	struct list_head *last = list->prev;

	first->prev = prev;
	prev->next = first;

	last->next = next;
	next->prev = last;
}

static inline void list_splice_tail(struct list_head *list,
				struct list_head *head)
{
	if (!list_empty(list))
		__list_splice(list, head->prev, head);
}

static inline void list_replace(struct list_head *old,
				struct list_head *new)
{
	new->next = old->next;
	new->next->prev = new;
	new->prev = old->prev;
	new->prev->next = new;
}

static inline void list_replace_init(struct list_head *old,
					struct list_head *new)
{
	list_replace(old, new);
	INIT_LIST_HEAD(old);
}

static int config_lists_init(void)
{
	INIT_LIST_HEAD(&list_configs);
	INIT_LIST_HEAD(&list_extracfgs);

	return 0;
}

static void config_lists_free(void)
{
	struct list_head *iter;
	struct list_head *tmp;
	struct list_head *head;
	struct cfg_list_item *n;

	if (!list_empty(&list_extracfgs))
		list_splice_tail(&list_extracfgs, &list_configs);
	head = &list_configs;
	list_for_each_safe(iter, tmp, head) {
		n = list_entry(iter, struct cfg_list_item, list);
		if (n) {
			list_del(&n->list);
			free(n);
		}
	}

	INIT_LIST_HEAD(&list_configs);
	INIT_LIST_HEAD(&list_extracfgs);
}

static void line_process(char *buf, int len /*@unused@*/)
{
	char *argv[32];
	int argc = 0;
	char *ptr = buf;
	char *head = buf;
	unsigned long int offset;
	uint8_t l;
	uint8_t i = 0;
	struct cfg_list_item *item;

	RS_INFO("%s", buf);

	while ((ptr = strsep(&head, ", \t")) != NULL) {
		if (!ptr[0])
			continue;
		argv[argc++] = ptr;
		if (argc >= 32) {
			RS_WARN("%s: Config item is too long", __func__);
			break;
		}
	}

	if (argc < 4) {
		RS_WARN("%s: Invalid Config item, ignore", __func__);
		return;
	}

	offset = strtoul(argv[0], NULL, 16);
	offset = offset | (strtoul(argv[1], NULL, 16) << 8);
	l = (uint8_t)strtoul(argv[2], NULL, 16);
	if (l != (uint8_t)(argc - 3)) {
		RS_ERR("Invalid Config item len %u", l);
		return;
	}

	item = malloc(sizeof(*item) + l);
	if (!item) {
		RS_WARN("%s: Cannot alloc mem for item, %04lx, %u", __func__,
			offset, l);
		return;
	}
	memset(item, 0, sizeof(*item));
	item->offset = (uint16_t)offset;
	item->len = l;
	for (i = 0; i < l; i++)
		item->data[i] = (uint8_t)strtoul(argv[3 + i], NULL, 16);
	list_add_tail(&item->list, &list_extracfgs);
}

static void config_process(uint8_t *buf, int len /*@unused@*/)
{
	char *head = (void *)buf;
	char *ptr = (void *)buf;

	while ((ptr = strsep(&head, "\n\r")) != NULL) {
		if (!ptr[0])
			continue;
		line_process(ptr, strlen(ptr) + 1);
	}
}

static void parse_extra_config(const char *path)
{
	int fd;
	uint8_t buf[256];
	int result;

	fd = open(path, O_RDONLY);
	if (fd == -1) {
		RS_INFO("Couldnt open extra config %s, %s", path,
			strerror(errno));
		return;
	}

	result = read(fd, buf, sizeof(buf));
	if (result == -1) {
		RS_ERR("Couldnt read %s, %s", path, strerror(errno));
		goto done;
	} else if (result == 0) {
		RS_ERR("File is empty");
		goto done;
	}

	if (result > 254) {
		RS_ERR("Extra Config file is too big");
		goto done;
	}
	buf[result++] = '\n';
	buf[result++] = '\0';

	config_process(buf, result);

done:
	close(fd);
}

/* Get the entry from patch_table according to LMP subversion */
struct patch_info *get_patch_entry(struct rtb_struct *btrtl)
{
	struct patch_info *n = NULL;

	if (btrtl->proto == HCI_UART_3WIRE)
		n = patch_table;
	else
		n = h4_patch_table;
	for (; n->lmp_subver; n++) {
		if ((n->match_flags & RTL_FW_MATCH_CHIP_TYPE) &&
		    n->chip_type != btrtl->chip_type)
			continue;
		if ((n->match_flags & RTL_FW_MATCH_HCI_VER) &&
		    n->hci_ver != btrtl->hci_ver)
			continue;
		if ((n->match_flags & RTL_FW_MATCH_HCI_REV) &&
		    n->hci_rev != btrtl->hci_rev)
			continue;
		if (n->lmp_subver != btrtl->lmp_subver)
			continue;

		break;
	}

	return n;
}

static int is_mac(uint8_t chip_type, uint16_t offset)
{
	int result = 0;

	switch (chip_type) {
	case CHIP_8822BS:
	case CHIP_8723DS:
	case CHIP_8821CS:
	case CHIP_8723CS_XX:
	case CHIP_8723CS_CG:
	case CHIP_8723CS_VF:
	case CHIP_8723CS:
		if (offset == 0x0044)
			return 1;
		break;
	case CHIP_8822CS:
	case CHIP_8761B:
	case CHIP_8852AS:
	case CHIP_8733BS:
	case CHIP_8852BS:
	case CHIP_8852CS:
	case CHIP_8851BS:
	case CHIP_8852DS:
	case CHIP_8922AS:
	case CHIP_8852BTS:
	case CHIP_8761CTV:
		if (offset == 0x0030)
			return 1;
		break;
//	case 0: /* special for not setting chip_type */
	case CHIP_8761AT:
	case CHIP_8761ATF:
	case CHIP_8761BTC:
	case CHIP_8723BS:
		if (offset == 0x003c)
			return 1;
		break;
	default:
		break;
	}

	return result;
}

static uint16_t get_mac_offset(uint8_t chip_type)
{
	switch (chip_type) {
	case CHIP_8822BS:
	case CHIP_8723DS:
	case CHIP_8821CS:
	case CHIP_8723CS_XX:
	case CHIP_8723CS_CG:
	case CHIP_8723CS_VF:
	case CHIP_8723CS:
		return 0x0044;
	case CHIP_8822CS:
	case CHIP_8761B:
	case CHIP_8852AS:
	case CHIP_8733BS:
	case CHIP_8852BS:
	case CHIP_8852CS:
	case CHIP_8851BS:
	case CHIP_8852DS:
	case CHIP_8922AS:
	case CHIP_8852BTS:
	case CHIP_8761CTV:
		return 0x0030;
//	case 0: /* special for not setting chip_type */
	case CHIP_8761AT:
	case CHIP_8761ATF:
	case CHIP_8761BTC:
	case CHIP_8723BS:
		return 0x003c;
	default:
		return 0x003c;
	}
}

static void merge_configs(struct list_head *head, struct list_head *head2)
{
	struct list_head *epos, *enext;
	struct list_head *pos, *next;
	struct cfg_list_item *n;
	struct cfg_list_item *extra;

	if (!head || !head2)
		return;

	if (list_empty(head2))
		return;

	if (list_empty(head)) {
		list_splice_tail(head2, head);
		INIT_LIST_HEAD(head2);
		return;
	}

	/* Add or update & replace */
	list_for_each_safe(epos, enext, head2) {
		extra = list_entry(epos, struct cfg_list_item, list);

		list_for_each_safe(pos, next, head) {
			n = list_entry(pos, struct cfg_list_item, list);
			if (extra->offset == n->offset) {
				if (extra->len < n->len) {
					/* Update the cfg data */
					RS_INFO("Update cfg: ofs %04x len %u",
						n->offset, n->len);
					memcpy(n->data, extra->data,
					       extra->len);
					list_del(epos);
					free(extra);
					break;
				} else {
					/* Replace the item */
					list_del(epos);
					list_replace_init(pos, epos);
					/* free the old item */
					free(n);
				}
			}

		}

	}

	if (list_empty(head2))
		return;
	list_for_each_safe(epos, enext, head2) {
		extra = list_entry(epos, struct cfg_list_item, list);
		RS_INFO("Add new cfg: ofs %04x, len %u", extra->offset,
			extra->len);
		/* Add the item to list */
		list_del(epos);
		list_add_tail(epos, head);
	}
}

/*
 * Parse realtek Bluetooth config file.
 * The content starts with vendor magic: 55 ab 23 87
 */
int rtb_parse_config(uint8_t *cfg_buf, size_t len)
{
	struct rtk_bt_vendor_config *config = (void *)cfg_buf;
	uint16_t cfg_len;
	uint16_t tmp;
	struct rtb_cfg_item *entry = NULL;
	uint16_t i;
	struct cfg_list_item *item;

	if (!cfg_buf || (len < RTB_CFG_HDR_LEN)) {
		RS_ERR("%s: Invalid parameter", __func__);
		return -1;
	}

	if (memcmp(cfg_buf, cfg_magic, 4)) {
		RS_ERR("Signature %02x %02x %02x %02x is incorrect",
		       cfg_buf[0], cfg_buf[1], cfg_buf[2], cfg_buf[3]);
		return -1;
	}

	cfg_len = le16_to_cpu(config->data_len);
	if (cfg_len != len - RTB_CFG_HDR_LEN) {
		RS_ERR("Config len %u is incorrect(%zd)", cfg_len,
		       len - RTB_CFG_HDR_LEN);
		return -1;
	}

	entry = config->entry;
	i = 0;
	while (i < cfg_len) {
		/* Add config item to list */
		item = malloc(sizeof(*item) + entry->len);
		if (item) {
			memset(item, 0, sizeof(*item));
			item->offset = le16_to_cpu(entry->offset);
			item->len = entry->len;
			memcpy(item->data, entry->data, item->len);
			list_add_tail(&item->list, &list_configs);
		} else {
			RS_ERR("Cannot alloc mem for entry %04x, %u",
			       entry->offset, entry->len);
		}

		tmp = entry->len + sizeof(struct rtb_cfg_item);
		i += tmp;
		entry = (struct rtb_cfg_item *)((uint8_t *)entry + tmp);
	}

	return 0;
}

static int bachk(const char *str)
{
	if (!str)
		return -1;

	if (strlen(str) != 17)
		return -1;

	while (*str) {
		if (!isxdigit(*str++))
			return -1;

		if (!isxdigit(*str++))
			return -1;

		if (*str == 0)
			break;

		if (*str++ != ':')
			return -1;
	}

	return 0;
}

/*
 * Get random Bluetooth addr.
 */
/* static void rtb_get_ram_addr(char bt_addr[0])
 * {
 * 	srand(time(NULL) + getpid() + getpid() * 987654 + rand());
 *
 * 	uint32_t addr = rand();
 * 	memcpy(bt_addr, &addr, sizeof(uint8_t));
 * }
 */

/*
 * Write the random addr to the BT_ADDR_FILE.
 */
/* static void rtb_write_btmac2file(char bt_addr[6])
 * {
 * 	int fd;
 * 	fd = open(BT_ADDR_FILE, O_CREAT | O_RDWR | O_TRUNC);
 *
 * 	if (fd > 0) {
 * 		chmod(BT_ADDR_FILE, 0666);
 * 		char addr[18] = { 0 };
 * 		addr[17] = '\0';
 * 		sprintf(addr, "%2x:%2x:%2x:%2x:%2x:%2x", bt_addr[0], bt_addr[1],
 * 			bt_addr[2], bt_addr[3], bt_addr[4], bt_addr[5]);
 * 		write(fd, addr, strlen(addr));
 * 		close(fd);
 * 	} else {
 * 		RS_ERR("open file error:%s\n", BT_ADDR_FILE);
 * 	}
 * }
 */

/*
 * Read and parse Realtek Bluetooth Config file.
 */
uint8_t *rtb_read_config(const char *file, int *cfg_len, uint8_t chip_type)
{
	char *file_name;
	struct stat st;
	ssize_t file_len;
	int fd;
	uint8_t *buf;
	size_t size;
	ssize_t result;
	struct list_head *pos, *next;
	struct cfg_list_item *n;
	uint16_t config_len;
	uint16_t dlen;
	uint32_t baudrate;
	uint8_t *p;

	if (!file || !cfg_len) {
		RS_ERR("%s: Invalid parameter", __func__);
		return NULL;
	}

	config_lists_init();

	/* All extra configs will be added to list_extracfgs */
	parse_extra_config(EXTRA_CONFIG_FILE);
	list_for_each_safe(pos, next, &list_extracfgs) {
		n = list_entry(pos, struct cfg_list_item, list);
		RS_INFO("extra cfg: ofs %04x, len %u", n->offset, n->len);
	}

	fd = open(BT_ADDR_FILE, O_RDONLY);
	if (fd == -1) {
		RS_INFO("Couldnt open BT MAC file %s, %s", BT_ADDR_FILE,
			strerror(errno));
	} else {
		uint16_t ofs;
		char *str;
		int i = 0;
		uint8_t bdaddr[6];
		uint8_t tbuf[BDADDR_STRING_LEN + 1];

		if (fstat(fd, &st) < 0) {
			RS_INFO("Couldnt access customer BT MAC file %s",
					BT_ADDR_FILE);
			close(fd);
			goto read_cfg;
		}

		size = st.st_size;
		/* Only read the first 17-byte if the file length is larger */
		if (size > BDADDR_STRING_LEN)
			size = BDADDR_STRING_LEN;

		memset(tbuf, 0, sizeof(tbuf));
		result = read(fd, tbuf, size);
		close(fd);
		if (result == -1) {
			RS_ERR("Couldnt read BT MAC file %s, err %s",
			       BT_ADDR_FILE, strerror(errno));
			goto read_cfg;
		}

		if (bachk((const char *)tbuf) < 0) {
			goto read_cfg;
		}

		str = (char *)tbuf;
		for (i = 5; i >= 0; i--) {
			bdaddr[i] = (uint8_t)strtoul(str, NULL, 16);
			str += 3;
		}

		/* Reserve LAP addr from 0x9e8b00 to 0x9e8b3f,
		 * Change to 0x008bXX */
		if (0x9e == bdaddr[3] && 0x8b == bdaddr[4] &&
		    bdaddr[5] <= 0x3f)
			bdaddr[3] = 0x00;

		RS_DBG("BT MAC %02x:%02x:%02x:%02x:%02x:%02x",
		       bdaddr[5], bdaddr[4], bdaddr[3], bdaddr[2],
		       bdaddr[1], bdaddr[0]);
		ofs = get_mac_offset(chip_type);
		n = malloc(sizeof(*n) + 6);
		if (n) {
			n->offset = ofs;
			n->len = 6;
			memcpy(n->data, bdaddr, 6);
			list_add_tail(&n->list, &list_extracfgs);
		} else {
			RS_ERR("Couldn't alloc cfg item for bdaddr");
		}
	}

read_cfg:
	*cfg_len = 0;
	file_name = malloc(PATH_MAX);
	if (!file_name) {
		RS_ERR("Can't allocate memory for Config file name");
		return NULL;
	}
	memset(file_name, 0, PATH_MAX);
	snprintf(file_name, PATH_MAX, "%s%s", BT_CONFIG_DIRECTORY, file);

	if ((fd = open(file_name, O_RDONLY)) < 0) {
		perror("Can't open Config file");
		goto err_open;
	}

	if (fstat(fd, &st) < 0) {
		RS_ERR("Can't access Config file: %s, %s",
		       file_name, strerror(errno));
		close(fd);
		goto err_stat;
	}
	file_len = st.st_size;

	buf = malloc(file_len);
	if (!buf) {
		RS_ERR("Couldnt malloc buffer for Config %zd", file_len);
		goto err_malloc;
	}

	result = read(fd, buf, file_len);
	if (result < (ssize_t)file_len) {
		perror("Can't read Config file");
		goto err_read;
	}
	close(fd);
	free(file_name);

	result = rtb_parse_config(buf, file_len);
	if (result < 0) {
		RS_ERR("Invalid Config content");
		free(buf);
		config_lists_free();
		exit(EXIT_FAILURE);
	}
	RS_INFO("Origin cfg len %u", (uint16_t)file_len);
	util_hexdump((const uint8_t *)buf, file_len);

	merge_configs(&list_configs, &list_extracfgs);

	config_len = 4; /* magic word length */
	config_len += 2; /* data length field */
	/* Calculate the config_len */
	dlen = 0;
	list_for_each_safe(pos, next, &list_configs) {
		n = list_entry(pos, struct cfg_list_item, list);
		switch (n->offset) {
		case 0x003c:
		case 0x0030:
		case 0x0044:
			if (is_mac(chip_type, n->offset) && n->len == 6) {
				char s[18];
				sprintf(s, "%2.2X:%2.2X:%2.2X:%2.2X:%2.2X:%2.2X",
					n->data[5], n->data[4],
					n->data[3], n->data[2],
					n->data[1], n->data[0]);
				RS_INFO("bdaddr ofs %04x, %s", n->offset, s);
			}
			break;
		case 0x000c:
#ifdef BAUDRATE_4BYTES
			baudrate = get_unaligned_le32(n->data);
#else
			baudrate = get_unaligned_le16(n->data);
#endif
			rtb_cfg.vendor_baud = baudrate;
			RS_INFO("Config baudrate: %08x", baudrate);

			if (n->len > 12) {
				uint8_t d = n->data[12];
				rtb_cfg.uart_flow_ctrl = (d & 0x4) ? 1 : 0;
				RS_INFO("uart flow ctrl: %u",
					rtb_cfg.uart_flow_ctrl);
			}
			break;
#ifdef RTL8723DSH4_UART_HWFLOWC
		case 0x0018:
			if (chip_type == CHIP_8723DS &&
			    rtb_cfg.proto == HCI_UART_H4) {
				if (n->data[0] & (1 << 2))
					rtb_cfg.uart_flow_ctrl = 1;
				RS_INFO("8723DSH4: hw flow control %u",
					rtb_cfg.uart_flow_ctrl);
				if (n->data[0] & 0x01) {
					rtb_cfg.parenb = 1;
					if (n->data[0] & 0x02)
						rtb_cfg.pareven = 1;
					else
						rtb_cfg.pareven = 0;
				}
				RS_INFO("8723DSH4: parity %u, even %u",
					rtb_cfg.parenb,
					rtb_cfg.pareven);
			}
			break;
#endif
		default:
			break;
		}

		config_len += (3 + n->len);
		dlen += (3 + n->len);

	}
	p = realloc(buf, config_len);
	if (!p) {
		/* block is left untouched; it is not freed or moved */
		RS_ERR("Couldn't realloc buf for configs");
		free(buf);
		buf = NULL;
		*cfg_len = 0;
		goto done;
	}
	buf = p;

	memcpy(buf, cfg_magic, 4);
	buf[4] = dlen & 0xff;
	buf[5] = (dlen >> 8) & 0xff;
	p = buf + 6;
	list_for_each_safe(pos, next, &list_configs) {
		n = list_entry(pos, struct cfg_list_item, list);
		p[0] = n->offset & 0xff;
		p[1] = (n->offset >> 8) & 0xff;
		p[2] = n->len;
		memcpy(p + 3, n->data, n->len);
		p += (3 + n->len);
	}

	RS_INFO("Vendor baud from Config file: %08x", rtb_cfg.vendor_baud);

	RS_INFO("New cfg len %u", config_len);
	util_hexdump((const uint8_t *)buf, config_len);

	*cfg_len = config_len;

done:
	config_lists_free();

	return buf;

err_read:
	free(buf);
err_malloc:
	config_lists_free();
	close(fd);
err_open:
err_stat:
	free(file_name);
	return NULL;
}

/*
 * Read Realtek Bluetooth firmaware file.
 */
uint8_t *rtb_read_firmware(struct rtb_struct *btrtl, int *fw_len)
{
	char *filename;
	struct stat st;
	int fd = -1;
	size_t fwsize;
	uint8_t *fw_buf;
	ssize_t result;

	if (!btrtl || !fw_len) {
		RS_ERR("%s: Invalid parameter", __func__);
		return NULL;
	}

	filename = malloc(PATH_MAX);
	if (!filename) {
		RS_ERR("Can't allocate memory for fw name");
		return NULL;
	}

	snprintf(filename, PATH_MAX, "%s%s", FIRMWARE_DIRECTORY,
		 btrtl->patch_ent->patch_file);

	if ((fd = open(filename, O_RDONLY)) < 0) {
		RS_ERR("Can't open firmware, %s", strerror(errno));
		goto err_open;
	}

	if (fstat(fd, &st) < 0) {
		RS_ERR("Can't access firmware %s, %s", filename,
		       strerror(errno));
		close(fd);
		goto err_stat;
	}

	fwsize = st.st_size;

	fw_buf = malloc(fwsize);
	if (!fw_buf) {
		RS_ERR("Can't allocate memory for fw, %s", strerror(errno));
		goto err_malloc;
	}

	result = read(fd, fw_buf, fwsize);
	if (result != (ssize_t) fwsize) {
		RS_ERR("Read FW %s error, %s", filename, strerror(errno));
		goto err_read;
	}

	*fw_len = (int)result;
	RS_INFO("Load FW %s OK, size %zd", filename, result);

	close(fd);
	free(filename);

	return fw_buf;

err_read:
	free(fw_buf);
	*fw_len = 0;
err_malloc:
	close(fd);
err_open:
err_stat:
	free(filename);
	return NULL;
}

static uint8_t rtb_get_fw_project_id(uint8_t *p_buf)
{
	uint8_t opcode;
	uint8_t len;
	uint8_t data = 0;

	do {
		opcode = *p_buf;
		len = *(p_buf - 1);
		if (opcode == 0x00) {
			if (len == 1) {
				data = *(p_buf - 2);
				RS_INFO("%s: opcode %u, len %u, data %u",
					__func__, opcode, len, data);
				break;
			} else {
				RS_ERR("%s: Invalid len %u", __func__, len);
			}
		}
		p_buf -= len + 2;
	} while (*p_buf != 0xFF);

	return data;
}

struct rtb_ota_flag {
	uint8_t eco;
	uint8_t enable;
	uint16_t reserve;
} __attribute__ ((packed));

struct patch_node {
	uint8_t eco;
	uint8_t pri;
	uint8_t key_id;
	uint8_t reserve;
	uint32_t len;
	uint8_t *payload;
	struct list_head list;
};

/* Add a node to alist that is in ascending order. */
void insert_queue_sort(struct list_head *head, struct patch_node *node)
{
	struct list_head *pos;
	struct list_head *next;
	struct patch_node *tmp;

	if(!head || !node) {
		return;
	}
	list_for_each_safe(pos, next, head) {
		tmp = list_entry(pos, struct patch_node, list);
		if(tmp->pri >= node->pri)
			break;
	}
	__list_add(&node->list, pos->prev, pos);
}

static int insert_patch(struct patch_node *patch_node_hdr, uint8_t *section_pos,
		uint32_t opcode, uint32_t *patch_len, uint8_t *sec_flag)
{
	struct rtb_struct *rtl = &rtb_cfg;
	struct patch_node *tmp;
	int i;
	uint32_t numbers;
	uint32_t section_len = 0;
	uint8_t eco = 0;
	uint8_t *pos = section_pos + 8;

	numbers = get_unaligned_le16(pos);
	RS_INFO("number 0x%04x", numbers);

	pos += 4;
	for (i = 0; i < numbers; i++) {
		eco = (uint8_t)*(pos);
		RS_INFO("eco 0x%02x, Eversion:%02x", eco, rtb_cfg.eversion);
		if (eco == rtb_cfg.eversion + 1) {
			tmp = (struct patch_node*)malloc(sizeof(struct patch_node));
			if (!tmp) {
				RS_ERR("Failed to allocate mem for tmp node");
				return -1;
			}
			tmp->pri = (uint8_t)*(pos + 1);
			if(opcode == PATCH_SECURITY_HEADER)
				tmp->key_id = (uint8_t)*(pos + 1);

			section_len = get_unaligned_le32(pos + 4);
			tmp->len =  section_len;
			*patch_len += section_len;
			RS_INFO("Pri:%d, Patch length 0x%04x", tmp->pri, tmp->len);
			tmp->payload = pos + 8;
			if(opcode != PATCH_SECURITY_HEADER) {
				insert_queue_sort(&(patch_node_hdr->list), tmp);
			} else {
				if((rtl->key_id == tmp->key_id) && (rtl->key_id > 0)) {
					insert_queue_sort(&(patch_node_hdr->list), tmp);
					*sec_flag = 1;
				} else {
					pos += (8 + section_len);
					free(tmp);
					continue;
				}
			}
		} else {
			section_len =  get_unaligned_le32(pos + 4);
			RS_INFO("Patch length 0x%04x", section_len);
		}
		pos += (8 + section_len);
	}
	return 0;
}

static uint8_t *rtb_get_patch_header(int *len,
		struct patch_node *patch_node_hdr, uint8_t * epatch_buf,
		uint8_t key_id)
{
	uint16_t i, j;
	struct rtb_new_patch_hdr *new_patch;
	uint8_t sec_flag = 0;
	uint32_t number_of_ota_flag;
	uint32_t patch_len = 0;
	uint8_t *section_pos;
	uint8_t *ota_flag_pos;

	struct rtb_section_hdr section_hdr;
	struct rtb_ota_flag ota_flag;

	new_patch = (struct rtb_new_patch_hdr *)epatch_buf;
	new_patch->number_of_section = le16_to_cpu(new_patch->number_of_section);

	RS_INFO("FW version 0x%02x,%02x,%02x,%02x,%02x,%02x,%02x,%02x",
				*(epatch_buf + 8), *(epatch_buf + 9), *(epatch_buf + 10),
				*(epatch_buf + 11),*(epatch_buf + 12), *(epatch_buf + 13),
				*(epatch_buf + 14), *(epatch_buf + 15));

	section_pos = epatch_buf + 20;

	for (i = 0; i < new_patch->number_of_section; i++) {
		section_hdr.opcode = get_unaligned_le32(section_pos);
		section_hdr.section_len = get_unaligned_le32(section_pos + 4);
		RS_INFO("opcode 0x%04x", section_hdr.opcode);

		switch (section_hdr.opcode) {
		case PATCH_SNIPPETS:
			if(insert_patch(patch_node_hdr, section_pos, PATCH_SNIPPETS, &patch_len, 0))
				goto alloc_fail;
			break;
		case PATCH_SECURITY_HEADER:
			if(!key_id)
				break;

			sec_flag = 0;
			if(insert_patch(patch_node_hdr, section_pos, PATCH_SECURITY_HEADER, &patch_len, &sec_flag))
				goto alloc_fail;
			if(sec_flag)
				break;

			for (i = 0; i < new_patch->number_of_section; i++) {
				section_hdr.opcode = get_unaligned_le32(section_pos);
				section_hdr.section_len = get_unaligned_le32(section_pos + 4);
				if(section_hdr.opcode == PATCH_DUMMY_HEADER) {
					if(insert_patch(patch_node_hdr, section_pos, PATCH_DUMMY_HEADER, &patch_len, 0))
						goto alloc_fail;
				}
				section_pos += (SECTION_HEADER_SIZE + section_hdr.section_len);
			}
			break;
		case PATCH_DUMMY_HEADER:
			if(key_id) {
				break;
			}
			if(insert_patch(patch_node_hdr, section_pos, PATCH_DUMMY_HEADER, &patch_len, 0))
				goto alloc_fail;
			break;
		case PATCH_OTA_FLAG:
			ota_flag_pos = section_pos + 4;
			number_of_ota_flag = get_unaligned_le32(ota_flag_pos);
			ota_flag.eco = (uint8_t)*(ota_flag_pos + 1);
			if (ota_flag.eco == rtb_cfg.eversion + 1) {
				for (j = 0; j < number_of_ota_flag; j++) {
					if (ota_flag.eco == rtb_cfg.eversion + 1) {
						ota_flag.enable = get_unaligned_le32(ota_flag_pos + 4);
					}
				}
			}
			break;
		default:
			RS_INFO("Unknown Opcode. Ignore");
		}
		section_pos += (SECTION_HEADER_SIZE + section_hdr.section_len);
	}
	*len = patch_len;

	return 0;
alloc_fail:
	*len = 0;
	return 0;
}

struct rtb_patch_entry *rtb_get_patch_entry(void)
{
	uint16_t i;
	struct rtb_patch_hdr *patch;
	struct rtb_patch_entry *entry;
	uint32_t tmp;
	uint8_t *ci_base; /* Chip id base */
	uint8_t *pl_base; /* Patch length base */
	uint8_t *so_base; /* Start offset base */

	patch = (struct rtb_patch_hdr *)rtb_cfg.fw_buf;
	entry = (struct rtb_patch_entry *)malloc(sizeof(*entry));
	if (!entry) {
		RS_ERR("Failed to allocate mem for patch entry");
		return NULL;
	}

	patch->number_of_patch = le16_to_cpu(patch->number_of_patch);

	RS_DBG("FW version 0x%08x, Patch num %u",
	       le32_to_cpu(patch->fw_version), patch->number_of_patch);

	ci_base = rtb_cfg.fw_buf + 14;
	pl_base = ci_base + 2 * patch->number_of_patch;
	so_base = pl_base + 2 * patch->number_of_patch;
	for (i = 0; i < patch->number_of_patch; i++) {
		uint16_t chip_id = get_unaligned_le16(ci_base + 2 * i);

		RS_INFO("Chip id 0x%04x", chip_id);
		if (chip_id == rtb_cfg.eversion + 1) {
			entry->chip_id = rtb_cfg.eversion + 1;
			entry->patch_len = get_unaligned_le16(pl_base + 2 * i);
			entry->soffset = get_unaligned_le32(so_base + 4 * i);
			RS_DBG("Patch length 0x%04x", entry->patch_len);
			RS_DBG("Start offset 0x%08x", entry->soffset);

			entry->svn_ver = get_unaligned_le32(rtb_cfg.fw_buf +
						entry->soffset +
						entry->patch_len - 8);
			entry->coex_ver = get_unaligned_le32(rtb_cfg.fw_buf +
						entry->soffset +
						entry->patch_len - 12);

			RS_INFO("Svn version: %8u", entry->svn_ver);
			tmp = ((entry->coex_ver >> 16) & 0x7ff) +
			      (entry->coex_ver >> 27) * 10000;
			RS_INFO("Coexistence: BTCOEX_20%06u-%04x\n", tmp,
				(entry->coex_ver & 0xffff));

			break;
		}
	}

	if (i == patch->number_of_patch) {
		RS_ERR("Failed to get entry");
		free(entry);
		entry = NULL;
	}

	return entry;
}

uint8_t *rtb_get_final_patch(int fd, int proto, int *rlen)
{
	struct rtb_struct *rtl = &rtb_cfg;
	uint8_t proj_id = 0;
	struct rtb_patch_entry *entry = NULL;
	struct rtb_patch_hdr *patch = (struct rtb_patch_hdr *)rtl->fw_buf;
	uint32_t svn_ver, coex_ver, tmp;
	uint8_t *buf;
	int len;

	struct list_head *pos, *next;
	struct patch_node *tmp_node;
	struct patch_node patch_node_hdr;

	if (!rlen) {
		RS_ERR("%s: Invalid parameter", __func__);
		return NULL;
	}

	/* Use single patch for 3wire && 8723a */
	if (proto == HCI_UART_3WIRE && rtl->lmp_subver == ROM_LMP_8723a) {
		if (!memcmp(rtl->fw_buf, RTK_EPATCH_SIGNATURE, 8)) {
			RS_ERR("Unexpected signature");
			goto err;
		}

		len = rtl->config_len + rtl->fw_len;
		buf = malloc(len);
		if (!buf) {
			RS_ERR("Can't alloc mem for fwc, %s", strerror(errno));
			goto err;
		} else {
			uint8_t *b;

			RS_INFO("FWC copy directly");

			b = rtl->fw_buf + rtl->fw_len;
			svn_ver = get_unaligned_le32(b - 8);
			coex_ver = get_unaligned_le32(b - 12);

			RS_INFO("Svn version: %u\n", svn_ver);
			tmp = ((coex_ver >> 16) & 0x7ff) +
			      (coex_ver >> 27) * 10000;
			RS_INFO("Coexistence: BTCOEX_20%06u-%04x\n", tmp,
				(coex_ver & 0xffff));

			/* Copy Patch and Config */
			memcpy(buf, rtl->fw_buf, rtl->fw_len);
			if (rtl->config_len)
				memcpy(buf + rtl->fw_len,
				       rtl->config_buf, rtl->config_len);
			rtl->dl_fw_flag = 1;
			*rlen = len;
			return buf;
		}
	}


	/* check Signature and Extension Section Field */
	if (((memcmp(rtl->fw_buf, RTK_EPATCH_SIGNATURE, 8) != 0) &&
		(memcmp(rtl->fw_buf, RTK_EPATCH_SIGNATURE_NEW, 8) != 0))||
		memcmp(rtl->fw_buf + rtl->fw_len - 4,
		Extension_Section_SIGNATURE, 4) != 0) {
		RS_ERR("Extension section signature error");
		goto err;
	}

	proj_id = rtb_get_fw_project_id(rtl->fw_buf + rtl->fw_len - 5);

#ifdef RTL_8703A_SUPPORT
	if (rtl->hci_ver == 0x4 && rtl->lmp_subver == ROM_LMP_8723b) {
		RS_INFO("HCI version = 0x4, IC is 8703A.");
	} else {

		RS_ERR("error: lmp_version 04%x, hci_version %x, proj_id %02x",
		       rtl->lmp_subver, rtl->hci_ver, proj_id);
		goto err;
	}
#else
	/* TODO: For 8703BS and 8723CS that have the same lmp subver, we don't
	 * verify the project id
	 */
	if (rtl->lmp_subver != ROM_LMP_8703b) {
		int i;

		for (i = 0; i < ARRAY_SIZE(project_id_to_lmp_subver); i++) {
			if (proj_id == project_id_to_lmp_subver[i].id &&
			    rtl->lmp_subver == project_id_to_lmp_subver[i].lmp_subver) {
				break;
			}
		}

		if (i >= ARRAY_SIZE(project_id_to_lmp_subver)) {
			RS_ERR("lmp_version %x, proj_id %x, not match",
			       rtl->lmp_subver, proj_id);
			goto err;
		}
	}
#endif
	INIT_LIST_HEAD(&patch_node_hdr.list);
	/* Entry is allocated dynamically. It should be freed later in the
	 * function.
	 */
	if(memcmp(rtl->fw_buf, RTK_EPATCH_SIGNATURE_NEW, 8) == 0) {
		rtb_vendor_read(fd, READ_SEC_PROJ);
		RS_INFO("%s: key id %d", __func__, rtl->key_id);
		rtb_get_patch_header(&len, &patch_node_hdr, rtl->fw_buf, rtl->key_id);
		if(len == 0)
			goto alloc_fail;
		RS_INFO("len = 0x%x", len);
		len += rtl->config_len;
	} else {
		entry = rtb_get_patch_entry();

		if (entry) {
			len = entry->patch_len + rtl->config_len;
		} else {
			RS_ERR("Can't find the patch entry");
			goto err;
		}
	}

	buf = malloc(len);
	if (!buf) {
		RS_ERR("%s: Can't alloc memory for fwc, %s", __func__,
		       strerror(errno));
		free(entry);
		goto err;
	} else {
		if(memcmp(rtl->fw_buf, RTK_EPATCH_SIGNATURE_NEW, 8) == 0) {
			int tmp_len = 0;
			list_for_each_safe(pos, next, &patch_node_hdr.list)
			{
				tmp_node = list_entry(pos, struct patch_node, list);
				RS_INFO("len = 0x%x", tmp_node->len);
				memcpy(buf + tmp_len, tmp_node->payload, tmp_node->len);
				tmp_len += tmp_node->len;
				list_del_init(pos);
				free(tmp_node);
			}
			if (rtl->config_len) {
				memcpy(&buf[len - rtl->config_len],
					rtl->config_buf,
					rtl->config_len);
			}
		} else {
			memcpy(buf, rtl->fw_buf + entry->soffset, entry->patch_len);
			memcpy(buf + entry->patch_len - 4, &patch->fw_version, 4);	/*fw version */

			if (rtl->config_len) {
				memcpy(&buf
					[len - rtl->config_len],
					rtl->config_buf,
					rtl->config_len);
			}
		}
		rtl->dl_fw_flag = 1;
		*rlen = len;
	}

	RS_INFO("FW %s exists, Config file %s exists",
		(rtl->fw_len > 0) ? "" : "not",
		(rtl->config_len > 0) ? "" : "not");

	free(entry);
	return buf;
err:
alloc_fail:
	rtl->dl_fw_flag = 0;
	*rlen = 0;
	return NULL;
}

