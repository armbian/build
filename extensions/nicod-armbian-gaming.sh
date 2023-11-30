#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Creates a launcher script for NicoD's armbian-gaming project.
# Script will clone (or pull if already cloned) from NicoD's repo and run his script.

function extension_prepare_config__800_nicod_launcher() {
	EXTRA_IMAGE_SUFFIXES+=("-gaming") # global array; '800' hook is pretty much at the end
	return 0
}

function pre_customize_image__add_nicod_launcher() {
	display_alert "Adding NicoD's armbian-gaming launcher" "${EXTENSION}" "info"

	local launcher_dir="${SDCARD}/usr/local/bin"
	local launcher_file="${launcher_dir}/nicod-armbian-gaming"
	run_host_command_logged mkdir -pv "${launcher_dir}"

	cat <<- 'NICOD_GAMING_LAUNCHER_SCRIPT' > "${launcher_file}"
		#!/usr/bin/env bash
		if [[ ! -d ~/armbian-gaming ]]; then
			git clone https://github.com/NicoD-SBC/armbian-gaming.git ~/armbian-gaming
		fi
		cd ~/armbian-gaming
		git pull || true
		bash armbian-gaming.sh "$@"
	NICOD_GAMING_LAUNCHER_SCRIPT

	run_host_command_logged chmod -v +x "${launcher_file}"
	display_alert "Added NicoD's armbian-gaming launcher" "${EXTENSION}" "info"
}
