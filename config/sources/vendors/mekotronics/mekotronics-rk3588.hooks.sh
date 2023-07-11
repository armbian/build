#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Vendor u-boot, standard rockchip, plus patches.
function post_family_config__uboot_mekotronics() {
	display_alert "$BOARD" "Configuring Mekotronics R58 ($BOARD) u-boot" "info"

	declare -g BOOTSOURCE='https://github.com/rockchip-linux/u-boot.git'
	#declare -g BOOTBRANCH='branch:next-dev' # disabled, using specific commit below to avoid breakage in the future
	declare -g BOOTBRANCH="commit:cc781e0266d589b937b5af9e4850fb1e7222f0f1" # specific commit in next-dev branch; tested to work

	declare -g BOOTDIR="u-boot-meko-rk3588"             # do not share u-boot directory
	declare -g BOOTPATCHDIR="legacy/u-boot-meko-rk3588" # Few patches in there; MAC address & defconfig

	declare -g OVERLAY_PREFIX='rockchip-rk3588'
	declare -g BOOTDELAY=1 # build injects this into u-boot config. we can then get into UMS mode and avoid the whole rockusb/rkdeveloptool thing
}
