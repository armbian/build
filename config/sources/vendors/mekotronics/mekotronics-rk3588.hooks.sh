#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Vendor u-boot; use the default family (rockchip-rk3588) u-boot. See config/sources/families/rockchip-rk3588.conf
function post_family_config__vendor_uboot_mekotronics() {
	display_alert "$BOARD" "Configuring $BOARD vendor u-boot" "info"
	declare -g BOOTDELAY=1 # build injects this into u-boot config. we can then get into UMS mode and avoid the whole rockusb/rkdeveloptool thing
}

# Conditional hook to allow experimenting with this against legacy/vendor branches
if [[ "${MEKO_USE_MAINLINE_UBOOT:-"no"}" == "yes" ]]; then
	# Mainline u-boot with generic rk3588 support from next branch upstream (2024-03-31) or Kwiboo's tree

	function post_family_config__meko_use_mainline_uboot() {
		display_alert "$BOARD" "mainline (next branch) u-boot overrides for $BOARD / $BRANCH" "info"

		declare -g BOOTCONFIG="generic-rk3588_defconfig" # MAINLINE U-BOOT OVERRIDE

		declare -g BOOTDELAY=1 # Wait for UART interrupt to enter UMS/RockUSB mode etc

		BOOTSOURCE="https://github.com/Kwiboo/u-boot-rockchip.git"
		BOOTBRANCH="branch:rk3xxx-2024.04"  # commit:31522fe7b3c7733313e1c5eb4e340487f6000196 as of 2024-04-01
		BOOTPATCHDIR="v2024.04-mekotronics" # empty

		BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory

		UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin" # NOT u-boot-rockchip-spi.bin
		unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd                                 # disable stuff from rockchip64_common; we're using binman here which does all the work already

		# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
		function write_uboot_platform() {
			dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
		}
	}
fi
