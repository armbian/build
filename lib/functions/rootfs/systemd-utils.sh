#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function disable_systemd_service_sdcard() {
	display_alert "Disabling systemd service(s) on target" "${*}" "debug"
	declare service stderr_output
	for service in "${@}"; do
		# Use --root= to operate directly on the chroot filesystem
		# instead of talking to the host's systemd via D-Bus (which
		# doesn't know about the chroot's unit files).
		stderr_output="$(systemctl --root="${SDCARD}" --no-reload disable "${service}" 2>&1)" || true
		[[ -n "${stderr_output}" ]] && display_alert "systemctl disable ${service}" "${stderr_output}" "debug"
	done
}
