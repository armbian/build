#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/

# This file is SOURCED by the Mekotronics board files, and thus has the same restrictions as board files.
# Especifically, the family code (rockchip64_common) will both require and override a bunch of stuff.
# We use hooks (post_family_config, etc) to be able to both reuse code and force certain values.
display_alert "shared vendor code" "Mekotronics (RK3588) config" "info"

# enable shared hooks (could be made into an extension)
source "${SRC}/config/sources/vendors/mekotronics/mekotronics-rk3588.hooks.sh"

# hciattach
declare -g BLUETOOTH_HCIATTACH_PARAMS="-s 115200 /dev/ttyS6 bcm43xx 1500000" # For the bluetooth-hciattach extension
enable_extension "bluetooth-hciattach"                                       # Enable the bluetooth-hciattach extension

# board-like config
declare -g BOOT_SCENARIO="spl-blobs" # so we don't depend on defconfig naming convention
declare -g BOOT_SOC="rk3588"         # so we don't depend on defconfig naming convention
declare -g IMAGE_PARTITION_TABLE="gpt"

# Uses default DDR_BLOB and BL31_BLOB from rockchip64_common.

# For the u-boot-menu extension (build with 'EXT=u-boot-menu')
declare -g SRC_CMDLINE="loglevel=7 console=ttyS2,1500000 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1"
