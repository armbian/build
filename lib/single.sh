#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Users should not start here, but instead use ./compile.sh at the root.
if [[ $(basename "$0") == single.sh ]]; then
	echo "Please use compile.sh to start the build process"
	exit 255
fi

# Libraries include. ONLY source files that contain ONLY functions here.

# shellcheck source=library-functions.sh
source "${SRC}"/lib/library-functions.sh
