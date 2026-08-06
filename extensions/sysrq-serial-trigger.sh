#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2026 Igor Velkov
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#
# Enable Magic SysRq through the serial console for headless boards. Without
# this, kernel hangs (NFS deadlocks, ATA error-handler corner cases on Helios64,
# etc.) leave you with no way out except the hardware-watchdog timeout or a
# physical reset. With it, an operator on the serial console can sync,
# remount-RO and reboot from any kernel state where interrupts still flow.
#
# This extension only enables the operator-console *surface*. To make the
# tracebacks and KGDB sessions reachable through that surface actually
# informative (rather than streams of hex addresses), pair with the
# `kernel-debug-tiers` extension which adds BTF, hung-task detection,
# pstore/ramoops, and KGDB symbol resolution.
#
# Mainline kernels ship CONFIG_MAGIC_SYSRQ_SERIAL_SEQUENCE empty by default,
# which disables BREAK-triggered SysRq entirely. From lib/Kconfig.debug:
# "If unsure, leave an empty string and the option will not be enabled."
# (https://elixir.bootlin.com/linux/latest/source/lib/Kconfig.debug#L698)
# The serial driver requires a non-empty sequence after BREAK so that random
# line noise cannot trigger a reboot. This extension fills that in with a
# deliberate sequence that is vanishingly unlikely in normal serial traffic.
#
# Usage — add to your userpatches config (e.g. `userpatches/config-my.conf`):
#
#     enable_extension "sysrq-serial-trigger"
#
# Or pass on the build CLI for a one-off run:
#
#     ./compile.sh build BOARD=helios64 BRANCH=edge \
#         ENABLE_EXTENSIONS=sysrq-serial-trigger
#
# Operator workflow (picocom default escape Ctrl-A):
#     Ctrl-A \      (send BREAK)
#     sysrq         (the magic sequence, default value of SYSRQ_SERIAL_SEQUENCE)
#     b             (or any other SysRq command — see Documentation/admin-guide/sysrq.rst)
#
# To experiment with a different sequence, override SYSRQ_SERIAL_SEQUENCE
# from the build CLI; pick something that does not occur in normal output of
# anything you care about (logging, dialog, etc.).

function custom_kernel_config__sysrq_serial_trigger() {
	# Default "sysrq": printable, easy to type, and passes through Bash/sed without
	# escaping. Kernel matches bytes verbatim against serial input after BREAK.
	# `:-` substitutes only when SYSRQ_SERIAL_SEQUENCE is unset; an explicit
	# empty value would otherwise silently write MAGIC_SYSRQ_SERIAL_SEQUENCE=""
	# which lib/Kconfig.debug documents as disabling BREAK-triggered SysRq
	# entirely. Refuse empty loudly so the operator fixes the config rather
	# than getting a silently-disabled SysRq path.
	declare seq="${SYSRQ_SERIAL_SEQUENCE:-sysrq}"
	if [[ -z "${seq}" ]]; then
		exit_with_error "${EXTENSION}: SYSRQ_SERIAL_SEQUENCE must not be empty" \
			"empty would write MAGIC_SYSRQ_SERIAL_SEQUENCE=\"\" and disable BREAK-triggered SysRq; pick any non-empty sequence (default: SYSRQ_SERIAL_SEQUENCE=sysrq)"
	fi
	display_alert "${EXTENSION}: enabling SysRq over serial" "sequence='${seq}' after BREAK" "info"
	opts_y+=("MAGIC_SYSRQ" "MAGIC_SYSRQ_SERIAL")
	# 1 = SYSRQ_ENABLE_ALL (kernel special-case, not bit 1); enables all SysRq
	# commands regardless of the runtime kernel.sysrq sysctl value at boot.
	# shellcheck disable=SC2034 # opts_val is read by armbian_kernel_config_apply_opts_from_arrays
	opts_val["MAGIC_SYSRQ_DEFAULT_ENABLE"]="1"
	# Armbian has no opts_str[] equivalent for string kconfig options — opts_val[]
	# dispatches via --set-val which truncates strings to "" (it is designed for
	# numeric/hex values only). Use kernel_config_set_string directly; it calls
	# --set-str and registers the value in kernel_config_modifying_hashes.
	# Two-phase guard: kernel_config_set_string requires an unpacked source tree;
	# in the hash-only phase (.config absent) add to hashes manually instead.
	if [[ -f .config ]]; then
		kernel_config_set_string "MAGIC_SYSRQ_SERIAL_SEQUENCE" "${seq}"
	else
		kernel_config_modifying_hashes+=("MAGIC_SYSRQ_SERIAL_SEQUENCE=\"${seq}\"")
	fi
}

# U-Boot autoboot timing — give the operator a real chance to interrupt.
# Default Armbian u-boot prints "Hit any key to stop autoboot: 0" — i.e.
# a 1-second window that's effectively unusable. BOOTDELAY=5 gives a 5-second
# countdown; AUTOBOOT_NEVER_TIMEOUT means a single keypress freezes the
# countdown entirely so the operator can take their time after that. The
# trade-off is +5s on every cold boot — acceptable for headless servers,
# probably annoying for kiosks. Comment out this whole function to revert.
function post_config_uboot_target__sysrq_serial_uboot_autoboot() {
	display_alert "${EXTENSION}: u-boot BOOTDELAY=5 + AUTOBOOT_NEVER_TIMEOUT" "give the operator 5s to grab the prompt; pause forever after first keypress" "info"
	# `scripts/config` is u-boot's own kbuild helper (same script as Linux uses).
	# It handles "is not set" → enabled and value-overrides correctly without
	# depending on which form the line currently takes.
	run_host_command_logged ./scripts/config --set-val CONFIG_BOOTDELAY 5
	run_host_command_logged ./scripts/config --enable CONFIG_AUTOBOOT_NEVER_TIMEOUT
}

# Distro defaults (Debian/Ubuntu /usr/lib/sysctl.d/55-magic-sysrq.conf) cap
# kernel.sysrq at 176 — enough for `s`/`u`/`b` but not `t`/`m`/`f`/`w` which
# are the actually useful debug commands when a kernel is misbehaving. A
# headless box with serial-console SysRq is exactly the case where the full
# set should be available, so override to 1 (all functions). The 60- prefix
# beats the 55- distro file in sysctl.d lexical order.
function post_customize_image__sysrq_serial_trigger_userland() {
	declare conf="${SDCARD}/etc/sysctl.d/60-armbian-sysrq.conf"
	display_alert "${EXTENSION}: enabling full kernel.sysrq" "${conf##*/} (kernel.sysrq=1)" "info"
	cat > "${conf}" <<- 'SYSCTL_CONF'
		# Installed by the Armbian sysrq-serial-trigger extension.
		# Overrides /usr/lib/sysctl.d/55-magic-sysrq.conf (default 176)
		# to enable the full SysRq command set — needed for serial-console
		# debugging (process dumps, blocked-task list, OOM kill, etc.).
		kernel.sysrq = 1
	SYSCTL_CONF
}
