#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
declare -g CRUST_TARGET_MAP="scp;;build/scp/scp.bin"

[[ -n "${CRUSTCONFIG}" && -z $CRUSTSOURCE ]] && CRUSTSOURCE='https://github.com/crust-firmware/crust'
[[ -n "${CRUSTCONFIG}" && -z $CRUSTDIR ]] && CRUSTDIR='crust-sunxi-mainline'
[[ -n "${CRUSTCONFIG}" && -z $CRUSTBRANCH ]] && CRUSTBRANCH='commit:c308a504853e7fdb47169796c9a832796410ece8'
[[ -n "${CRUSTCONFIG}" && -z $CRUST_USE_GCC ]] && CRUST_USE_GCC='> 9.1.0'
[[ -n "${CRUSTCONFIG}" && -z $CRUST_COMPILER ]] && CRUST_COMPILER='or1k-elf-'

# Apply crust patches if crust is enabled
[[ -n "${CRUSTCONFIG}" ]] && BOOTPATCHDIR="${BOOTPATCHDIR} u-boot-sunxi-crust"

# Use a different BOOTDIR so that we don't leave scp.bin behind for non crust builds
[[ -n "${CRUSTCONFIG}" ]] && BOOTDIR="u-boot-crust"

# complain about system not being supported for building crust image
function add_host_dependencies__dont_try_to_build_crust_on_unsupported_systems() {
    if [[ -n "${CRUSTCONFIG}" ]] ; then
        if [[ -z $HOSTRELEASE || "bookworm sid jammy kinetic lunar vanessa vera" != *"$HOSTRELEASE"* ]] ; then
            if [[ $NO_HOST_RELEASE_CHECK == yes ]]; then
                display_alert "You are running on an unsupported system" "${HOSTRELEASE:-(unknown)}" "wrn"
                display_alert "Do not report any errors, warnings or other issues encountered beyond this point" "" "wrn"
            else
                exit_with_error "Unsupported build system for images with crust-firmware: '${HOSTRELEASE:-(unknown)}'"
            fi
        fi
    fi
}
