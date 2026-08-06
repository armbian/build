#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2026 Igor Velkov
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#
# Enable cumulative kernel debug-information tiers for headless boards that
# need to be debugged through their serial console. On its own this extension
# does nothing visible at runtime — it just bakes enough information into the
# kernel that the operator-console facilities (Magic SysRq, KGDB, pstore) and
# any tracebacks they print are actually useful rather than streams of hex
# addresses.
#
# Pair with the `sysrq-serial-trigger` extension (kconfig + sysctl + u-boot
# autoboot delay) to actually have an operator-controllable surface; that
# extension turns the facilities ON, this one makes them MEANINGFUL.
#
# Tiers are cumulative: KERNEL_DEBUG_TIER=N enables every tier ≤ N.
#
#   0  no-op (extension stays loaded, kernel side disabled — keeps the
#      extension declarable in a shared config without forcing the cost on
#      every board, e.g. when one board needs BTF=no for RAM reasons)
#   1  printk timestamps + lockup/hung-task detection + stack guards
#      Cost: a handful of bytes per printk, a few cycles per scheduler tick.
#      No board prerequisites. Default tier.
#   2  + pstore/ramoops (persistent dmesg through reboot)
#      Cost: same as tier 1 plus a reserved memory region. Without a DT
#      `/reserved-memory/ramoops` node or `ramoops.mem_address=…` bootargs,
#      the modules load but have nowhere to write — silent no-op.
#   3  + KGDB / KDB over serial
#      Cost: same as tier 2 plus larger kernel image. Needs `kgdboc=<port>,<baud>`
#      in bootargs; without it the dispatcher is in-kernel but unreachable.
#
# BTF requirement: from tier 1 onwards this extension needs DEBUG_INFO_BTF=y
# (Armbian's default unless KERNEL_BTF=no). Without BTF, hung-task tracebacks
# and KGDB symbol output collapse to address-only — the whole point of the
# extension is then defeated. So an explicit `KERNEL_BTF=no` (in board/family
# conf or on the build CLI) combined with KERNEL_DEBUG_TIER>=1 is treated as
# a hard error: pick one, not both.
#
# Usage — add to your userpatches config (e.g. `userpatches/config-my.conf`):
#
#     enable_extension "kernel-debug-tiers"
#     KERNEL_DEBUG_TIER=2                          # default 1 if unset
#
# Or pass on the build CLI for a one-off run:
#
#     ./compile.sh build BOARD=helios64 BRANCH=edge \
#         ENABLE_EXTENSIONS=kernel-debug-tiers KERNEL_DEBUG_TIER=3

function extension_prepare_config__kernel_debug_tiers() {
	declare tier="${KERNEL_DEBUG_TIER:-1}"
	case "${tier}" in
		0 | 1 | 2 | 3) ;;
		*) exit_with_error "${EXTENSION}: KERNEL_DEBUG_TIER must be 0, 1, 2 or 3" "got '${tier}'" ;;
	esac

	# Tier 0 is a deliberate no-op — extension declared but kernel side off.
	# Skip the BTF check so a shared config can switch BTF on/off per board.
	if [[ "${tier}" == "0" ]]; then
		display_alert "${EXTENSION}: KERNEL_DEBUG_TIER=0" "extension loaded but kernel-side debug disabled" "info"
		return 0
	fi

	# Hard-fail on conflicting BTF preference. Armbian disables BTF (and all
	# DEBUG_INFO) when KERNEL_BTF=no — that strips the very symbols this
	# extension's tracebacks rely on.
	if [[ "${KERNEL_BTF}" == "no" ]]; then
		exit_with_error \
			"${EXTENSION}: KERNEL_BTF=no conflicts with KERNEL_DEBUG_TIER=${tier}" \
			"BTF is required for hung-task tracebacks and KGDB symbol resolution; either set KERNEL_BTF=yes (or leave it unset for Armbian's default) or set KERNEL_DEBUG_TIER=0 to disable this extension's kernel side"
	fi

	# Make BTF explicit so Armbian's default-BTF-on path is unambiguous in logs
	# even when the user didn't set KERNEL_BTF themselves.
	declare -g KERNEL_BTF="${KERNEL_BTF:-yes}"
	display_alert "${EXTENSION}: KERNEL_DEBUG_TIER=${tier}" "BTF=${KERNEL_BTF}" "info"
}

# Tier 1: low-cost diagnostics. printk timestamps and PRINTK_CALLER add a few
# bytes per line; stack-end check and lockup detectors cost a few cycles per
# scheduler tick. Cheap enough to ship on a headless server with serial debug.
function custom_kernel_config__kernel_debug_tier1() {
	if [[ "${KERNEL_DEBUG_TIER:-1}" -lt 1 ]]; then
		return 0
	fi
	display_alert "${EXTENSION}: tier 1" "printk timestamps + lockup/hung-task detection" "info"
	opts_y+=(
		"PRINTK_TIME"
		"PRINTK_CALLER"
		"DETECT_HUNG_TASK"
		"SOFTLOCKUP_DETECTOR"
		"SCHED_STACK_END_CHECK"
	)
	# Default is 120s upstream; explicit so the value shows up in .config.
	opts_val["DEFAULT_HUNG_TASK_TIMEOUT"]="120"
}

# Tier 2: pstore/ramoops — kernel writes its last printk before crash to a
# reserved memory region; userspace reads /sys/fs/pstore/dmesg-ramoops-0
# after the reboot. Catch: needs a memory region reserved either via
# `/reserved-memory/ramoops { ... }` in the device tree, or via bootargs
# `ramoops.mem_address=<phys> ramoops.mem_size=0x100000 ramoops.console_size=0x40000`.
# Without that the modules load but have nowhere to write — silent no-op.
function custom_kernel_config__kernel_debug_tier2_pstore() {
	if [[ "${KERNEL_DEBUG_TIER:-1}" -lt 2 ]]; then
		return 0
	fi
	display_alert "${EXTENSION}: tier 2 (pstore/ramoops)" "needs DT or bootarg reservation, otherwise no-op" "info"
	opts_y+=("PSTORE" "PSTORE_CONSOLE" "PSTORE_RAM" "PSTORE_DEFLATE_COMPRESS")
}

# Tier 3: KGDB/KDB over the serial console. SysRq+g drops into the KDB shell
# on the same line as the kernel printk — `bt`, `dmesg`, `lsmod`, `dis`,
# watchpoints. Needs `kgdboc=<console>,<baud>` in bootargs (e.g.
# `kgdboc=ttyS2,1500000` on Helios64) for the dispatcher to attach to the
# port; without that the kconfig is enabled but unreachable.
function custom_kernel_config__kernel_debug_tier3_kgdb() {
	if [[ "${KERNEL_DEBUG_TIER:-1}" -lt 3 ]]; then
		return 0
	fi
	display_alert "${EXTENSION}: tier 3 (KGDB)" "remember kgdboc=<port>,<baud> in bootargs" "info"
	opts_y+=(
		"KGDB"
		"KGDB_SERIAL_CONSOLE"
		"KGDB_KDB"
		"KGDB_LOW_LEVEL_TRAP"
	)
	# 0xFF = enable every KDB command (memory peek, register inspect, single
	# step, etc.). On a locked-down production box this can be masked down —
	# bits are documented in Documentation/dev-tools/kgdb.rst.
	# shellcheck disable=SC2034 # opts_val is read by armbian_kernel_config_apply_opts_from_arrays
	opts_val["KDB_DEFAULT_ENABLE"]="0xFF"
}
