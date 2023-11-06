#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
declare -g CRUST_TARGET_MAP="scp;;build/scp/scp.bin"

if [[ -n "${CRUSTCONFIG}" ]]; then
    [[ -z $CRUSTSOURCE ]] && CRUSTSOURCE='https://github.com/crust-firmware/crust'
    [[ -z $CRUSTDIR ]] && CRUSTDIR='crust-sunxi-mainline'
    [[ -z $CRUSTBRANCH ]] && CRUSTBRANCH='tag:v0.6'
    [[ -z $CRUST_USE_GCC ]] && CRUST_USE_GCC='> 9.1.0'
    [[ -z $CRUST_COMPILER ]] && CRUST_COMPILER='or1k-elf-'

    # Apply crust patches if crust is enabled
    BOOTPATCHDIR="${BOOTPATCHDIR} u-boot-sunxi-crust"

    # Use a different BOOTDIR so that we don't leave scp.bin behind for non crust builds
    BOOTDIR="u-boot-crust"
fi