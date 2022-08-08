#!/bin/sh
#
# Copyright (c) Authors: https://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
	OutstandingPackages="$(grep -Ev "linux-base|linux-image" /var/run/reboot-required.pkgs 2>/dev/null)"
	if [ -f "/var/run/.reboot_required" ]; then
		printf "\n[\e[0;91m Kernel was updated, please reboot\x1B[0m ]\n\n"
	elif [ "X${OutstandingPackages}" != "X" ]; then
		# No kernel update involved, just regular packages like e.g. dbus require a reboot
		Packages="$(grep -Ev "linux-base|linux-image" /var/run/reboot-required.pkgs | sort | uniq | tr '\n' ',' | sed -e 's/,/, /g' -e 's/,\ $//')"
		OlderThanOneDay=$(find /var/run/reboot-required -mtime +1)
	        if [ "X${OlderThanOneDay}" = "X" ]; then
			printf "\n[\e[0;92m some packages require a reboot (${Packages})\x1B[0m ]\n\n"
	        else
			printf "\n[\e[0;91m some packages require a reboot since more than 1 day (${Packages})\x1B[0m ]\n\n"
	        fi
	fi
fi
