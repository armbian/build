#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
# Copyright (c) 2013-2023 Jacob Hrbek, kreyren@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#

# Generic configuration for the riscv64 architecture

ARCH="riscv64"

OPENSBI_COMPILE="yes"

INITRD_ARCH="riscv"

GOVERNOR="ondemand"

NAME_KERNEL="Image"

NAME_INITRD="uInitrd"

MAIN_CMDLINE="rw no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0"

KERNEL_IMAGE_TYPE="Image"

SKIP_BOOTSPLASH="yes"

KERNELDIR="linux-riscv"

# UEFI_GRUB_TARGET="riscv64-efi"
