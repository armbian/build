/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * (C) Copyright 2020 Aditya Prayoga <aditya@kobol.io>
 */

#ifndef __HELIOS64_H
#define __HELIOS64_H

/* Override default boot targets before including common config. */
#define BOOT_TARGETS	"mmc1 mmc0 scsi0 usb0 pxe dhcp"

#include <configs/rk3399_common.h>

#endif /* __HELIOS64_H */
