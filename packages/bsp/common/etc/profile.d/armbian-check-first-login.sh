#!/bin/sh
#
# Copyright (c) Authors: https://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# First login as root?
if [ -w /root/ -a -f /root/.not_logged_in_yet ]; then
	bash /usr/lib/armbian/armbian-firstlogin
fi
