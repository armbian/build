#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
# Fix u-boot.itb missing dependency on u-boot.dtb.
#
# Background:
#   The FIT image generation script (arch/arm/mach-rockchip/make_fit_atf.sh)
#   references ./u-boot.dtb for the FDT node via /incbin/("./u-boot.dtb").
#   However, the u-boot.itb Makefile rule only depends on dts/dt.dtb, not
#   on u-boot.dtb (which is a separate copy target). With parallel make (-j),
#   this creates a race condition: mkfitimage may run before u-boot.dtb is
#   copied from dts/dt.dtb, resulting in a zero-size FDT in the FIT image.
#
# Affected U-Boot versions:
#   - Radxa fork (next-dev-v2024.10): single-line rule
#   - Mainline U-Boot (v2025.10): multi-line rule with \ continuations
#
# Fix:
#   Add u-boot.dtb as an explicit prerequisite of u-boot.itb, ensuring
#   the copy completes before the FIT image is assembled.
#
# This hook is safe for all U-Boot versions: it only patches when the
# problematic rule exists and u-boot.dtb is not already a dependency.

function pre_config_uboot_target__fix_itb_dtb_dependency() {
	# Guard 1: skip if the Makefile has no u-boot.itb target at all
	if ! grep -q '^u-boot\.itb:' Makefile; then
		return 0
	fi

	# Guard 2: skip if u-boot.dtb is already listed as a dependency
	if grep -q 'u-boot\.itb:.*u-boot\.dtb' Makefile; then
		return 0
	fi

	display_alert "Patching Makefile" "adding u-boot.dtb as u-boot.itb dependency" "info"

	# Use Python for robust multi-line matching.
	# Handles both single-line (Radxa fork) and multi-line continuation
	# (upstream v2025.10) formats of the u-boot.itb rule.
	python3 << 'PYTHON_SCRIPT'
import re
import sys

with open("Makefile", "r") as f:
    content = f.read()

# Match the u-boot.itb rule from its declaration to the terminating FORCE.
# - ^u-boot\.itb:        start of the rule line
# - [\s\S]*?             shortest match across lines (non-greedy)
# - \bFORCE\s*$          FORCE at end of a line (may be on continuation line)
# re.MULTILINE: ^ and $ match start/end of each line
pattern = r'(^u-boot\.itb:[\s\S]*?\bFORCE\s*$)'
match = re.search(pattern, content, re.MULTILINE)

if not match:
    print("u-boot.itb rule not found or unexpected format, skipping patch")
    sys.exit(0)

rule_text = match.group(1)

# Skip if already patched (double-check inside the matched rule)
if "u-boot.dtb" in rule_text:
    print("u-boot.dtb already in u-boot.itb dependencies, skipping")
    sys.exit(0)

# Insert "u-boot.dtb " before FORCE at the end of the rule
new_rule = re.sub(r'\bFORCE\s*$', r'u-boot.dtb FORCE', rule_text, count=1)

if new_rule == rule_text:
    print("Failed to insert u-boot.dtb dependency, skipping")
    sys.exit(0)

# Replace the old rule with the patched rule in the full content
content = content[:match.start()] + new_rule + content[match.end():]

with open("Makefile", "w") as f:
    f.write(content)

print("Makefile patched: u-boot.dtb added as u-boot.itb dependency")
PYTHON_SCRIPT

	display_alert "Makefile patched" "u-boot.dtb added as u-boot.itb dependency" "info"
}
