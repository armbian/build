#!/bin/sh
#
# Copyright (c) Authors: https://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# First login as root?
if [ -w /root/ -a -f /root/.not_logged_in_yet ]; then
	# The graphical wizard (armbian-firstrun-gui) runs on the screen: do not start a second setup.
	# A login on SSH, a serial console or another text console can take the setup over, for
	# example when no one is at the screen. The lock of armbian-firstlogin stops this while
	# the wizard applies its answers. Without a terminal, armbian-firstlogin does nothing.
	if [ -t 0 ] && systemctl -q is-active armbian-firstrun-gui.service 2> /dev/null; then
		echo "The first-run setup runs on the screen."
		printf "Stop it and continue the setup here? [y/N] "
		read -r reply
		case "$reply" in
			[yY]*)
				if flock -n /run/armbian-firstlogin.lock systemctl stop armbian-firstrun-gui.service; then
					reply=taken
					bash /usr/lib/armbian/armbian-firstlogin
				else
					echo "The setup on the screen applies its answers."
				fi
				;;
		esac
		if [ "$reply" != taken ]; then
			if [ -n "${SSH_CONNECTION}" ]; then
				echo "Log in again when it is complete."
			else
				# A console login (root autologin at first boot) must not stay open after
				# the setup. If the wizard stops without a result, continue the setup here.
				# Ctrl-C must not leave a root shell open.
				echo "This console logs out when the setup is complete."
				trap '' INT
				while [ -f /root/.not_logged_in_yet ] && systemctl -q is-active armbian-firstrun-gui.service; do
					sleep 1
				done
				trap - INT
				if [ -f /root/.not_logged_in_yet ]; then
					bash /usr/lib/armbian/armbian-firstlogin
				else
					kill -HUP $$
				fi
			fi
		fi
	else
		bash /usr/lib/armbian/armbian-firstlogin
	fi
fi
