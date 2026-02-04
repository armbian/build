#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Vendor u-boot
# Override the stuff from rockchip-rk3588 family; Meko's have a patch for stable MAC address that breaks with Radxa's next-dev-v2024.10+
function post_family_config__vendor_uboot_mekotronics() {
	# Don't do it if forcing mainline u-boot or on edge/current branches
	if [[ "${MEKO_USE_MAINLINE_UBOOT:-"no"}" == "yes" || "${BRANCH}" == "edge" || "${BRANCH}" == "current" ]]; then
		return 0 # separate, conditional hook below
	fi

	display_alert "$BOARD" "Configuring $BOARD vendor u-boot" "info"
	declare -g BOOTDELAY=1 # build injects this into u-boot config. we can then get into UMS mode and avoid the whole rockusb/rkdeveloptool thing

	declare -g BOOTSOURCE='https://github.com/radxa/u-boot.git'
	declare -g BOOTBRANCH='branch:next-dev-v2024.03' # NOT next-dev-v2024.10
	declare -g BOOTPATCHDIR="legacy/u-boot-radxa-rk35xx"
}

# Conditional hook to allow experimenting with this against legacy/vendor branches
if [[ "${MEKO_USE_MAINLINE_UBOOT:-"no"}" == "yes" ]]; then
	# Mainline u-boot with generic rk3588 support; no pci/usb/ethernet but should work SD/eMMC and UMS/Gadget mode

	function post_family_config__meko_use_mainline_uboot() {
		display_alert "$BOARD" "mainline (next branch) u-boot overrides for $BOARD / $BRANCH" "info"

		declare -g BOOTCONFIG="generic-rk3588_defconfig" # MAINLINE U-BOOT OVERRIDE
		declare -g BOOTDELAY=1                           # Wait for UART interrupt

		declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
		declare -g BOOTBRANCH="tag:v2026.01"
		declare -g BOOTPATCHDIR="v2026.01"

		BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory

		UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-usb471.bin u-boot-rockchip-usb472.bin"
		unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

		# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
		function write_uboot_platform() {
			dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
		}

		declare -g PLYMOUTH="no" # Disable plymouth as that only causes more confusion
	}

	function post_config_uboot_target__extra_configs_for_meko_mainline_uboot() {
		display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable RAMBoot images" "info"
		run_host_command_logged scripts/config --enable CONFIG_ROCKCHIP_MASKROM_IMAGE
	}

fi
