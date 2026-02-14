#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Armbian
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

function post_family_config__add_uwe5622_modules() {
	declare -g MODULES="${MODULES} sprdbt_tty"
	add_packages_to_image rfkill bluetooth bluez bluez-tools
}

function post_family_tweaks__enable_uwe5622_services() {
	# install and enable Bluetooth
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable aw859a-bluetooth.service >/dev/null 2>&1"
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable aw859a-wifi.service >/dev/null 2>&1"
}

function post_family_tweaks_bsp__add_uwe5622_services() {
	run_host_command_logged mkdir -p "${destination}/lib/systemd/system/"
	run_host_command_logged cp "${SRC}/packages/bsp/sunxi/aw859a-bluetooth.service" "${destination}/lib/systemd/system/"
	run_host_command_logged cp "${SRC}/packages/bsp/sunxi/aw859a-wifi.service" "${destination}/lib/systemd/system/"
	run_host_command_logged install -m 755 "${SRC}/packages/blobs/bt/hciattach/hciattach_opi_${ARCH}" "${destination}/usr/bin/hciattach_opi"
}
