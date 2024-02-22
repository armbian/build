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
declare -g BOOT_SCENARIO="spl-blobs"                    # so we don't depend on defconfig naming convention
declare -g BOOT_SOC="rk3588"                            # so we don't depend on defconfig naming convention
declare -g BOOTCONFIG="rk3588_meko_defconfig" # generic ebv plus distro dtb hacks
declare -g IMAGE_PARTITION_TABLE="gpt"

# newer blobs from rockchip. tested to work.
# set as variables, early, so they're picked up by `prepare_boot_configuration()`
declare -g DDR_BLOB='rk35/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.11.bin'
declare -g BL31_BLOB='rk35/rk3588_bl31_v1.38.elf'
