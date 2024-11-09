#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
declare -g SERIALCON="${SERIALCON:-tty1}"            # Consistent serial console device unlikely on UEFI arch pair. Customize if otherwise.
declare -g UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-3} # Default 3-seconds timeout for GRUB menu.
declare -g BOARD_FIRMWARE_INSTALL="-full"            # Install full firmware for UEFI boards
declare -g DISTRO_GENERIC_KERNEL=no

case "${BRANCH}" in

	ddk)
		# This will force `KERNELSOURCE='none'` later; no kernel will be built.
		# Instead, the distro's default linux-generic kernel will be installed.
		# rpardini: For some regrettable reason, most of this logic is in the grub extension.
		declare -g DISTRO_GENERIC_KERNEL=yes
		;;

	legacy)
		declare -g KERNEL_MAJOR_MINOR="6.1"
		;;

	current)
		declare -g KERNEL_MAJOR_MINOR="6.6"
		;;

	edge)
		declare -g KERNEL_MAJOR_MINOR="6.12"
		;;
esac

# Common for all branches
declare -g LINUXCONFIG="linux-uefi-${LINUXFAMILY}-${BRANCH}"
declare -g KERNELPATCHDIR="archive/uefi-${LINUXFAMILY}-${KERNEL_MAJOR_MINOR}" # Might be empty; NO SYMLINKS! Attention: KERNEL_MAJOR_MINOR is used, not BRANCH! No symlinks!

# Booting EFI stuff via GRUB. There are specific boards (qemu-uboot-x86 and qemu-uboot-arm64) that enable QEMU_UBOOT_BOOTCONFIG.
# This does not affect "normal" generic UEFI boards
if [[ "${QEMU_UBOOT_BOOTCONFIG}" != "" ]]; then
	# Allowance for using the UEFI kernels, but not an UEFI bootloader, instead, use qemu with uboot.
	# Used in the qemu-uboot-x86 and qemu-uboot-arm64 "boards".
	display_alert "Using UEFI as base for qemu-uboot-${LINUXFAMILY}" "Using BOOTCONFIG: ${QEMU_UBOOT_BOOTCONFIG}" "debug"
	declare -g ATF_COMPILE="no"

	declare -g BOOTDIR="qemu-uboot-${LINUXFAMILY}"
	declare -g BOOTBRANCH='tag:v2023.10'
	declare -g BOOTSOURCE='https://github.com/u-boot/u-boot' # Gotta set this again, it is unset by grub extension

	declare -g BOOTCONFIG="${QEMU_UBOOT_BOOTCONFIG}"
	add_packages_to_image spice-vdagent qemu-guest-agent # Nice-to-have packages for running under qemu

	# A patch to convert to `q35` machine type DTS (x86 only)
	declare -g BOOTPATCHDIR="u-boot-qemu-${LINUXFAMILY}"

	# Config for the qcow2 image
	declare -g QCOW2_RESIZE_AMOUNT="+50G" # resize the qcow2 image to be 50G bigger
	declare -g QCOW2_KEEP_IMG="no"        # produce only the .qcow2 image, not raw .img

	# Enable the qcow2 output extension.
	enable_extension "image-output-qcow2"

	write_uboot_platform() {
		echo "Not writing uboot for qemu-uboot-xxxx platform"
	}

fi
