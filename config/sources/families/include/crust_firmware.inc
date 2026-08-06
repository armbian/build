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
	[[ -z $CRUST_COMPILER ]] && CRUST_COMPILER='or1k-elf-'

	# Crust/SCP patchdir. v2026.07+ has native SCP (binman scp.bin node +
	# auto CONFIG_SUNXI_SCP_BASE), so it uses an empty dir; the legacy
	# u-boot-sunxi-crust set (h3-scp.patch) only forward-applies to v2024.01.
	BOOTPATCHDIR="${BOOTPATCHDIR} v2026.07-sunxi-crust"

	# Use a different BOOTDIR so that we don't leave scp.bin behind for non crust builds
	BOOTDIR="u-boot-crust"
fi
