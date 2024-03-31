#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# DISABLED: Vendor u-boot, standard rockchip, plus patches.
function DISABLED_post_family_config_branch_legacy__uboot_mekotronics() {
	display_alert "$BOARD" "Configuring Mekotronics R58 ($BOARD) u-boot" "info"

	declare -g BOOTSOURCE='https://github.com/radxa/u-boot.git'
	#declare -g BOOTBRANCH='branch:next-dev' # disabled, using specific commit below to avoid breakage in the future
	declare -g BOOTBRANCH="commit:609a77ef6e99c56aacd4b8d8f9c3056378f9c761" # specific commit in next-dev branch; tested to work

	declare -g BOOTDIR="u-boot-meko-rk3588"             # do not share u-boot directory
	declare -g BOOTPATCHDIR="legacy/u-boot-meko-rk3588" # Few patches in there; MAC address & defconfig

	declare -g OVERLAY_PREFIX='rockchip-rk3588'
	declare -g BOOTDELAY=1 # build injects this into u-boot config. we can then get into UMS mode and avoid the whole rockusb/rkdeveloptool thing
}

# Mainline u-boot with generic rk3588 support from next branch upstream (2024-03-31)

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__meko_use_mainline_uboot() {
	display_alert "$BOARD" "mainline (next branch) u-boot overrides for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="generic-rk3588_defconfig" # MAINLINE U-BOOT OVERRIDE - for all boards - maybe nanopc-t6-rk3588_defconfig ?

	declare -g BOOTDELAY=1 # Wait for UART interrupt to enter UMS/RockUSB mode etc

	BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	BOOTBRANCH="commit:27795dd717dadc73091e1b4d6c50952b93aaa819" # head of `branch:next` as of 2024-03-31
	BOOTPATCHDIR="v2024.04-mekotronics"                          # empty

	BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory

	UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin" # NOT u-boot-rockchip-spi.bin
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd                                 # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd if=${1}/u-boot-rockchip.bin of=${2} bs=32k seek=1 conv=fsync
	}
}

# I'm FED UP with this, lets make part of core
function add_host_dependencies__new_uboot_wants_pyelftools() {
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} python3-pyelftools" # @TODO: convert to array later
}
