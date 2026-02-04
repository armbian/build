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
declare -g POWER_MANAGEMENT_FEATURES=yes             # Suspend and resume might work well in UEFI, elsewhere is disabled by default

case "${BRANCH}" in

	ddk)
		# This will force `KERNELSOURCE='none'` later; no kernel will be built.
		# Instead, the distro's default linux-generic kernel will be installed.
		# rpardini: For some regrettable reason, most of this logic is in the grub extension.
		declare -g DISTRO_GENERIC_KERNEL=yes
		;;
	cloud)
		declare -g GRUB_CMDLINE_LINUX_DEFAULT="selinux=0 loglevel=3 max_loop=32"
		declare -g KERNEL_MAJOR_MINOR="6.18"
		declare -g LINUXCONFIG="linux-uefi-${LINUXFAMILY}-cloud"
		declare -g INSTALL_ARMBIAN_FIRMWARE="no"
		declare -g EXTRAWIFI="no"
		declare -g UEFI_GRUB_TIMEOUT=0
		declare -g QCOW2_RESIZE_AMOUNT="16G"
		# add additional packages to the image
		display_alert "Add additional packages to the image" "qemu-guest-agent spice-vdagent" "debug"
		add_packages_to_image qemu-guest-agent spice-vdagent
		;;

	legacy)
		declare -g KERNEL_MAJOR_MINOR="6.12"
		;;

	current)
		declare -g KERNEL_MAJOR_MINOR="6.18"
		;;

	edge)
		declare -g KERNEL_MAJOR_MINOR="6.19"
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
	declare -g BOOTBRANCH='tag:v2025.10'
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

function pre_customize_image__disable_few_armbian_services() {
	display_alert "Disabling Armbian services that are not needed for UEFI" "${BOARD}" "info"
	chroot_sdcard systemctl disable armbian-hardware-monitor.service "||" true
	chroot_sdcard systemctl disable armbian-hardware-optimize.service "||" true
	chroot_sdcard systemctl disable armbian-led-state.service "||" true
}

function custom_kernel_config__enable_amd_dc() {
	# Enables AMD Display Controller (DC) support for AMD GPUs
	# This enables the display engine for AMD Radeon graphics cards,
	# including DCN (Display Core Next) and DSC (Display Stream Compression)
	# Only enabled for UEFI boards, excluding cloud branch
	if [[ "${BRANCH}" != "cloud" ]]; then
		display_alert "Enabling AMD DC support" "UEFI family ${LINUXFAMILY}" "debug"
		opts_y+=("DRM_AMD_DC")
		opts_y+=("DRM_AMD_DC_DCN")
		opts_y+=("DRM_AMD_DC_DSC_SUPPORT")
	fi
}
