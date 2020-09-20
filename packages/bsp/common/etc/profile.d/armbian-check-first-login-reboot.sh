#!/bin/sh
#
# Copyright (c) Authors: http://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
	if [ -f "/var/run/.reboot_required" ]; then
		printf "\n[\e[0;91m Kernel was updated, please reboot\x1B[0m ]\n\n"
	fi
fi
