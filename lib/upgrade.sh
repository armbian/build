#!/bin/bash

# Copyright (c) 2015-2017 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2015-2017 other Armbian contributors (https://github.com/armbian/build/graphs/contributors)
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is part of the Armbian build script https://github.com/armbian/build/

# Show info messages about changed directory structure
# when updating from older build script versions

TTY_X=$(($(stty size | awk '{print $2}')-6)) # determine terminal width
TTY_Y=$(($(stty size | awk '{print $1}')-6)) # determine terminal height

if [[ $(basename "$0") == main.sh ]]; then
	echo "Please use compile.sh to start the build process"
	exit 255
fi

if [[ $(basename "$0") == compile.sh ]]; then
	# assuming dialog was installed already since this is supposed to be shown only on upgrade from previous versions
	dialog --title "Directory structure change notice" --colors --msgbox "Build script directory structure was changed to simplify the build environment setup, \
	simplify upgrading in the future and improve compatibility with containers like Docker and Vagrant

	To upgrade please clone the repository \Z4https://github.com/armbian/build/\Zn into an empty directory and launch \Z2compile.sh\Zn
	Copying and editing compile.sh is not required, build configuration is defined in \Z1config-*.conf\Zn files
	Default build configuration is defined in \Z1config-default.conf\Zn (created on first build script run)

	Sorry for the inconvenience" $TTY_Y $TTY_X
	exit 255
fi
