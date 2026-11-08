#!/bin/sh
#
# Copyright (c) Authors: https://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# acticate profile sync daemon

if [ -f "${HOME}/.activate_psd" ]; then
	rm -f "${HOME}/.activate_psd"
	/usr/bin/psd >/dev/null 2>&1
	config_file="${HOME}/.config/psd/psd.conf"
	# psd 6.x only: overlayfs mode is an option and needs psd-overlay-helper.
	# psd 7 and later always use fuse-overlayfs and have no USE_OVERLAYFS.
	if [ -x /usr/bin/psd-overlay-helper ] && [ -f "${config_file}" ]; then
		# test for overlayfs
		# TODO: don't enable on btrfs
		sed -i 's/#USE_OVERLAYFS=.*/USE_OVERLAYFS="yes"/' "${config_file}"
		case $(/usr/bin/psd p 2>/dev/null | grep Overlayfs) in
			*active*)
				printf '\n Configured profile sync daemon with overlayfs.\n'
				;;
			*)
				printf '\n Configured profile sync daemon.\n'
				sed -i 's/USE_OVERLAYFS="yes"/#USE_OVERLAYFS="no"/' "${config_file}"
				;;
		esac
	fi
	systemctl --user enable psd.service >/dev/null 2>&1
	systemctl --user start psd.service >/dev/null 2>&1
fi
