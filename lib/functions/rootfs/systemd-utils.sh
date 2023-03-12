#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function disable_systemd_service_sdcard() {
	display_alert "Disabling systemd service(s) on target" "${*}" "debug"
	declare service
	for service in "${@}"; do
		chroot_sdcard systemctl --no-reload disable "${service}" "||" true
	done
}
