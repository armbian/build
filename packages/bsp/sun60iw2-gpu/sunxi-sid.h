/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright(c) 2020 - 2023 Allwinner Technology Co.,Ltd. All rights reserved. */
/*
 * Copyright(c) 2014-2016 Allwinnertech Co., Ltd.
 *         http://www.allwinnertech.com
 *
 * Author: sunny <sunny@allwinnertech.com>
 *
 * allwinner sunxi soc chip version and chip id manager.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

/*
 * Vendored verbatim from the Orange Pi kernel source we build against:
 *   orangepi-xunlong/linux-orangepi @ orange-pi-6.6-sun60iw2 : bsp/include/sunxi-sid.h
 * Armbian's linux-headers package omits the bsp/ subtree, so the img-bxm-dkms
 * GPU module (sunxi_platform.c does '#include <sunxi-sid.h>') can't find it.
 * Shipped in the image and staged onto the compiler -I path by
 * enable-powervr-gpu so the DKMS build has it offline. See README.md.
 */

#ifndef __SUNXI_SID_H
#define __SUNXI_SID_H

#include <linux/types.h>
#include <linux/errno.h>

/* About ChipID of version */
#define SUNXI_CHIP_REV(p, v)  (p + v)

#define SUNXI_CHIP_SUN8IW6   (0x16730000)
#define SUN8IW6P1_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW6, 0x0000)
#define SUN8IW6P1_REV_B SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW6, 0x0001)

#define SUNXI_CHIP_SUN8IW7   (0x16800000)
#define SUN8IW7P1_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW7, 0x0000)
#define SUN8IW7P1_REV_B SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW7, 0x0001)
#define SUN8IW7P2_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW7, 0x0100)
#define SUN8IW7P2_REV_B SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW7, 0x0101)

#define SUNXI_CHIP_SUN8IW8P1 (0x16810000)
#define SUN8IW8P1_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW8P1, 0x0000)
#define SUN8IW8P1_REV_B SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW8P1, 0x0001)

#define SUNXI_CHIP_SUN8IW11   (0x17010000)
#define SUN8IW11P1_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW11, 0x0000)
#define SUN8IW11P2_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW11, 0x0001)
#define SUN8IW11P3_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW11, 0x0011)
#define SUN8IW11P4_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW11, 0x0101)

#define SUNXI_CHIP_SUN8IW12   (0x17210000)
#define SUN8IW12P1_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW12, 0x0000)

#define SUNXI_CHIP_SUN8IW15   (0x17550000)
#define SUN8IW15P1_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW15, 0x0000)

#define SUNXI_CHIP_SUN8IW16   (0x18160000)
#define SUN8IW16P1_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW16, 0x0000)
#define SUN8IW16P1_REV_B SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW16, 0x0001)

#define SUNXI_CHIP_SUN8IW19   (0x18170000)
#define SUN8IW19P1_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW19, 0x0000)

#define SUNXI_CHIP_SUN8IW21   (0x18860000)
#define SUN8IW21P1_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW21, 0x0000)

#define SUNXI_CHIP_SUN8IW17   (0x17080000)
#define SUN8IW17P1_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW17, 0x0000)

#define SUNXI_CHIP_SUN8IW18   (0x18210000)
#define SUN8IW18P1_REV_A SUNXI_CHIP_REV(SUNXI_CHIP_SUN8IW18, 0x0000)

#define SUNXI_CHIP_SUN50IW1   (0x16890000)
#define SUN50IW1P1_REV_A	SUNXI_CHIP_REV(SUNXI_CHIP_SUN50IW1, 0x0)

#define SUNXI_CHIP_SUN50IW2   (0x17180000)
#define SUN50IW2P1_REV_A	SUNXI_CHIP_REV(SUNXI_CHIP_SUN50IW2, 0x0)

#define SUNXI_CHIP_SUN50IW3   (0x17190000)
#define SUN50IW3P1_REV_A	SUNXI_CHIP_REV(SUNXI_CHIP_SUN50IW3, 0x0)

#define SUNXI_CHIP_SUN50IW6   (0x17280000)
#define SUN50IW6P1_REV_A	SUNXI_CHIP_REV(SUNXI_CHIP_SUN50IW6, 0x0)

#define SUNXI_CHIP_SUN50IW9   (0x18230000)
#define SUN50IW9P1_REV_A	SUNXI_CHIP_REV(SUNXI_CHIP_SUN50IW9, 0x0)
#define SUN50IW9P1_REV_B	SUNXI_CHIP_REV(SUNXI_CHIP_SUN50IW9, 0x1)

#define SUNXI_CHIP_SUN50IW10  (0x18550000)
#define SUN50IW10P1_REV_A	SUNXI_CHIP_REV(SUNXI_CHIP_SUN50IW10, 0x0)

#define SUNXI_CHIP_SUN50IW11  (0x18510000)
#define SUN50IW11P1_REV_A	SUNXI_CHIP_REV(SUNXI_CHIP_SUN50IW11, 0x0)
#define SUN50IW11P1_REV_B	SUNXI_CHIP_REV(SUNXI_CHIP_SUN50IW11, 0x1)
#define SUN50IW11P1_REV_C	SUNXI_CHIP_REV(SUNXI_CHIP_SUN50IW11, 0x2)

/* The key info in Efuse */

#define EFUSE_CHIPID_NAME	"chipid"
#define EFUSE_BROM_CONF_NAME	"brom_conf"
#define EFUSE_BROM_TRY_NAME	"brom_try"
#define EFUSE_BROM_NAME  	"brom"
#define EFUSE_TRIM_NAME		"trim"
#define EFUSE_THM_SENSOR_NAME   "thermal_sensor"
#define EFUSE_FT_ZONE_NAME	"ft_zone"
#define EFUSE_RESTRICT_NAME     "restrict"
#define EFUSE_FTCP_NAME         "ft_cp"
#define EFUSE_TV_OUT_NAME       "tvout"
#define EFUSE_TVE_NAME          "tve"
#define EFUSE_OEM_NAME          "oem"
#define EFUSE_ANTI_BLUSH_NAME   "anti_blushing"

#define EFUSE_PSENSOR_NAME      "psensor"
#define EFUSE_DDR_CFG_NAME      "ddr_cfg"
#define EFUSE_LDOA_NAME         "ldoa"
#define EFUSE_LDOB_NAME         "ldob"
#define EFUSE_AUDIO_BIAS_NAME   "audio_bias"
#define EFUSE_GAMMA_NAME        "gamma"
#define EFUSE_WR_PROTECT_NAME   "write_protect"
#define EFUSE_RD_PROTECT_NAME   "read_protect"
#define EFUSE_IN_NAME           "in"
#define EFUSE_ID_NAME           "id"
#define EFUSE_ROTPK_NAME        "rotpk"
#define EFUSE_SSK_NAME          "ssk"
#define EFUSE_RSSK_NAME         "rssk"
#define EFUSE_HDCP_HASH_NAME    "hdcp_hash"
#define EFUSE_HDCP_PKF_NAME     "hdcp_pkf"
#define EFUSE_HDCP_DUK_NAME     "hdcp_duk"
#define EFUSE_EK_HASH_NAME      "ek_hash"
#define EFUSE_SN_NAME           "sn"
#define EFUSE_NV1_NAME          "nv1"
#define EFUSE_NV2_NAME          "nv2"
#define EFUSE_BACKUP_KEY_NAME   "backup_key"
#define EFUSE_BACKUP_KEY2_NAME  "backup_key2"
#define EFUSE_TCON_PARM_NAME    "tcon_parm"
#define EFUSE_RSAKEY_HASH_NAME  "rsakey_hash"
#define EFUSE_RENEW_NAME        "renewability"
#define EFUSE_OPT_ID_NAME       "operator_id"
#define EFUSE_LIFE_CYCLE_NAME   "life_cycle"
#define EFUSE_JTAG_SECU_NAME    "jtag_security"
#define EFUSE_JTAG_ATTR_NAME    "jtag_attr"
#define EFUSE_CHIP_CONF_NAME    "chip_config"
#define EFUSE_RESERVED_NAME     "reserved"
#define EFUSE_RESERVED2_NAME    "reserved2"

#define SUNXI_KEY_NAME_LEN	32

#define SID_PRCTL		0x40
#define SID_RDKEY		0x60
#define SID_OP_LOCK		0xAC  /* In SID_PRCTL */

#define EFUSE_CHIPID_BASE	"allwinner,sunxi-chipid"
#define EFUSE_SID_BASE		"allwinner,sunxi-sid"
#define SRAM_CTRL_BASE		"allwinner,sram_ctrl"

#define EFUSE_MAX_ADDR_SIZE     (256)
#define EFUSE_RW_MAX_LEN        (64)
#define SUNXI_EFUSE_RAM_OFFSET	0x200

typedef struct {
	char name[64];
	uint32_t len;
	uint32_t offset;
	uint64_t key_data;
} sunxi_efuse_key_info_t;

#define sunxi_efuse_read(key_name, read_buf) \
		sunxi_efuse_readn(key_name, read_buf, 1024)

/* The interface functions */
#if IS_ENABLED(CONFIG_AW_SID)
unsigned int sunxi_get_soc_ver(void);
int sunxi_get_sid_ver(u32 *ver);
unsigned int sunxi_get_soc_ver_from_reg(void);
unsigned int sunxi_get_platform_id(void);
int sunxi_get_soc_chipid(unsigned char *chipid);
int sunxi_get_soc_chipid_str(char *chipid);
int sunxi_get_soc_chipid_origin(char *chipid_origin);
int sunxi_get_soc_ft_zone_str(char *serial);
int sunxi_get_soc_rotpk_status_str(char *status);
int sunxi_get_pmu_chipid(unsigned char *chipid);
int sunxi_get_serial(unsigned char *serial);
unsigned int sunxi_get_soc_bin(void);
int sunxi_soc_is_secure(void);
s32 sunxi_get_platform(s8 *buf, s32 size);
s32 sunxi_efuse_readn(s8 *key_name, void *buf, u32 n);
int sunxi_get_module_param_from_sid(u32 *dst, u32 offset, u32 len);
unsigned int sunxi_get_soc_markid(void);
int sunxi_sid_sram_read32(const char *key, u32 *data);
int sunxi_sid_get_ecc_status(void);
int sunxi_get_soc_dvfs(u32 *dvfs);
#else
unsigned int __attribute__((weak)) sunxi_get_soc_ver(void) { return -ENOSYS; }
int __attribute__((weak)) sunxi_get_sid_ver(u32 *ver) { return -ENOSYS; }
unsigned int __attribute__((weak)) sunxi_get_soc_ver_from_reg(void) { return -ENOSYS; }
unsigned int __attribute__((weak)) sunxi_get_platform_id(void) { return -ENOSYS; }
int __attribute__((weak)) sunxi_get_soc_chipid(unsigned char *chipid) { return -ENOSYS; }
int __attribute__((weak)) sunxi_get_soc_chipid_str(char *chipid) { return -ENOSYS; }
int __attribute__((weak)) sunxi_get_soc_chipid_origin(char *chipid_origin) { return -ENOSYS; }
int __attribute__((weak)) sunxi_get_soc_ft_zone_str(char *serial) { return -ENOSYS; }
int __attribute__((weak)) sunxi_get_soc_rotpk_status_str(char *status) { return -ENOSYS; }
int __attribute__((weak)) sunxi_get_pmu_chipid(unsigned char *chipid) { return -ENOSYS; }
int __attribute__((weak)) sunxi_get_serial(unsigned char *serial) { return -ENOSYS; }
unsigned int __attribute__((weak)) sunxi_get_soc_bin(void) { return -ENOSYS; }
int __attribute__((weak)) sunxi_soc_is_secure(void) { return -ENOSYS; }
s32 __attribute__((weak)) sunxi_get_platform(s8 *buf, s32 size) { return -ENOSYS; }
s32 __attribute__((weak)) sunxi_efuse_readn(s8 *key_name, void *buf, u32 n) { return -ENOSYS; }
int __attribute__((weak)) sunxi_get_module_param_from_sid(u32 *dst, u32 offset, u32 len) { return -ENOSYS; }
unsigned int __attribute__((weak)) sunxi_get_soc_markid(void) { return -ENOSYS; }
int __attribute__((weak))sunxi_sid_sram_read32(const char *key, u32 *data) { return -ENOSYS; }
int __attribute__((weak)) sunxi_sid_get_ecc_status(void) { return -ENOSYS; }
int __attribute__((weak)) sunxi_get_soc_dvfs(u32 *dvfs) { return -ENOSYS; }
#endif  /* CONFIG_AW_SID */

#endif  /* __SUNXI_SID_H */
