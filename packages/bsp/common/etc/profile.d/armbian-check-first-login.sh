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
	if systemctl -q is-active armbian-firstrun-gui.service 2> /dev/null; then
		echo "The first-run setup runs on the screen. Log in again when it is complete."
	else
		bash /usr/lib/armbian/armbian-firstlogin
	fi
fi
