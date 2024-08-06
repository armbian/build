#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Armbian
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Install 40-serverflags.conf in xorg.conf.d directory because autodetection
# may be faulty on some x.org revisions.
function post_family_tweaks_bsp__install_lima_serverflags() {

	display_alert "${EXTENSION} ${BOARD}" "adding lima x.org serverflags workaround to BSP" "info"

	declare xorg_conf_dir="/etc/X11/xorg.conf.d"
	declare conf_lima_file="40-serverflags.conf"
	run_host_command_logged mkdir -pv "${destination}${xorg_conf_dir}"

	cat <<- LIMA_SERVERFLAGS > "${destination}${xorg_conf_dir}/${conf_lima_file}"
		Section "ServerFlags"
		    Option  "AutoAddGPU" "off"
		    Option "Debug" "dmabuf_capable"
		EndSection

		Section "OutputClass"
		    Identifier "Lima"
		    Driver "modesetting"
		    MatchDriver "rockchip"
		    Option "AccelMethod" "glamor"
		    Option "PrimaryGPU" "true"
		EndSection
	LIMA_SERVERFLAGS

	return 0
}
