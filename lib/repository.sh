#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# This script shows packages in local repository

# load user config
[[ -f "../userpatches/lib.config" ]] && source "../userpatches/lib.config"

# define debs path
POT="../output/debs/"

# load functions
source general.sh

DISTROS=("jessie" "xenial" "stretch")

ParseOptions() {
	case $@ in
		show)
			# display repository content
			for release in "${DISTROS[@]}"; do
				display_alert "Displaying repository contents for" "$release" "ext"
				aptly repo show -with-packages -config=../config/aptly.conf $release | tail -n +7
			done
			echo "done."
			exit 0
			;;
		update)
			# display full help test
			# run repository update
			addtorepo
			# add a key to repo
			cp ../config/armbian.key ../output/repository/public
			echo "done."
			exit 0
			;;
		*)
			DisplayUsage
			exit 0
			;;
	esac
} # ParseOptions

DisplayUsage() {
	echo -e "Usage: repository show | update\n"
} # DisplayUsage

ParseOptions "$@"