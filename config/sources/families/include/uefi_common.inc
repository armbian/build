#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
declare -g SERIALCON="tty1"                          # Cant reasonably expect UEFI stuff to have a serial console. Customize if otherwise.
declare -g SKIP_BOOTSPLASH="yes"                     # No splash.
declare -g UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-3} # Default 3-seconds timeout for GRUB menu.
declare -g BOARD_FIRMWARE_INSTALL="-full"            # Install full firmware for UEFI boards
case "${BRANCH}" in

	ddk)
		# This will force `unset KERNELSOURCE` later; no kernel will be built.
		# Instead, the distro's default linux-generic kernel will be installed.
		declare -g DISTRO_GENERIC_KERNEL=yes
		;;

	legacy)

		declare -g DISTRO_GENERIC_KERNEL=no
		declare -g LINUXCONFIG="linux-uefi-${LINUXFAMILY}-${BRANCH}"
		declare -g KERNEL_MAJOR_MINOR="5.15"                      # Major and minor versions of this kernel. For mainline caching.
		declare -g KERNELBRANCH="branch:linux-5.15.y"             # Branch or tag to build from. It should match MAJOR_MINOR
		declare -g KERNELPATCHDIR="uefi-${LINUXFAMILY}-${BRANCH}" # Might be empty.
		;;

	current)

		declare -g DISTRO_GENERIC_KERNEL=no
		declare -g LINUXCONFIG="linux-uefi-${LINUXFAMILY}-${BRANCH}"
		declare -g KERNEL_MAJOR_MINOR="6.1"                       # Major and minor versions of this kernel. For mainline caching.
		declare -g KERNELBRANCH="branch:linux-6.1.y"              # Branch or tag to build from. It should match MAJOR_MINOR
		declare -g KERNELPATCHDIR="uefi-${LINUXFAMILY}-${BRANCH}" # Might be empty.
		;;

	edge)

		declare -g DISTRO_GENERIC_KERNEL=no
		declare -g LINUXCONFIG="linux-uefi-${LINUXFAMILY}-${BRANCH}"
		declare -g KERNEL_MAJOR_MINOR="6.2"                       # Major and minor versions of this kernel. For mainline caching.
		declare -g KERNELBRANCH="branch:linux-6.2.y"              # Branch or tag to build from. It should match MAJOR_MINOR
		declare -g KERNELPATCHDIR="uefi-${LINUXFAMILY}-${BRANCH}" # Might be empty.
		;;
esac

if [[ "${QEMU_UBOOT_BOOTCONFIG}" != "" ]]; then
	# Allowance for using the UEFI kernels, but not an UEFI bootloader, instead, use qemu with uboot.
	# Used in the qemu-uboot-x86 and qemu-uboot-arm64 "boards".
	display_alert "Using UEFI as base for qemu-uboot-${LINUXFAMILY}" "Using BOOTCONFIG: ${QEMU_UBOOT_BOOTCONFIG}" "debug"
	declare -g ATF_COMPILE="no"
	declare -g BOOTSCRIPT="boot-qemu-${LINUXFAMILY}.cmd:boot.cmd"
	declare -g BOOTDIR="qemu-uboot-${LINUXFAMILY}"
	declare -g BOOTBRANCH='tag:v2023.01'
	declare -g BOOTSOURCE='https://github.com/u-boot/u-boot' # Gotta set this again, it is unset by grub extension
	declare -g UBOOT_TARGET_MAP="all;;u-boot.rom"            # Can't find the target that produces 'u-boot.rom', so for now 'make all'
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

	function pre_umount_final_image__export_uboot_rom() {
		local uboot_name="${CHOSEN_UBOOT}_${REVISION}_${ARCH}"
		display_alert "Exporting u-boot.rom" "${uboot_name} - ${version}.u-boot.rom" "debug"
		run_host_command_logged cp -pv "${MOUNT}/usr/lib/${uboot_name}/u-boot.rom" "${DESTIMG}/${version}.u-boot.rom" || true
	}
fi
