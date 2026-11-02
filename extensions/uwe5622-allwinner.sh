# @description Enables the Spreadtrum UWE5622 (AW859A) WiFi/Bluetooth combo on Allwinner boards. Adds the `sprdbt_tty` module and `bluez`/`rfkill` packages, installs the `aw859a-wifi` and `aw859a-bluetooth` systemd services, ships `/etc/modprobe.d/sprdwl_ng.conf` (`disable_powersave=1`), and installs the `aw859a-bt-attach` helper (stock BlueZ `btattach` with the driver's in-kernel PSKEY/RF init, or the `hciattach_opi` blob when `sprdbt_tty vendor_init=0`). Enable on sunxi boards carrying this chip.

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
	# Attach helper: stock BlueZ btattach with the in-kernel vendor init (default),
	# or the vendor hciattach_opi when sprdbt_tty is loaded with vendor_init=0.
	# The blob stays installed until the in-kernel path is verified on every board.
	run_host_command_logged install -m 755 "${SRC}/packages/bsp/sunxi/aw859a-bt-attach" "${destination}/usr/sbin/aw859a-bt-attach"
	run_host_command_logged install -m 755 "${SRC}/packages/blobs/bt/hciattach/hciattach_opi_${ARCH}" "${destination}/usr/bin/hciattach_opi"

	# The WCN firmware acknowledges its own power-down request while frames are
	# still in flight (armbian/uwe5622 PR #28, open issue 1). Right after a cold
	# boot that happens during the 4-way handshake: the EAPOL frames go
	# unanswered, the AP deauthenticates ~11 s later and the first connection
	# takes 12-25 s longer; the same stall shows up as RX drops on an idle link.
	# Keeping the firmware awake costs idle power but makes the link reliable,
	# which is what every board using this chip wants by default. Users can
	# override by dropping a later-sorting file into /etc/modprobe.d.
	run_host_command_logged mkdir -p "${destination}/etc/modprobe.d/"
	cat <<- EOT > "${destination}/etc/modprobe.d/sprdwl_ng.conf"
		# UWE5622 (AW859A) WLAN: keep the firmware out of power save, see
		# https://github.com/armbian/uwe5622/pull/18 and /pull/28
		options sprdwl_ng disable_powersave=1
	EOT
}
