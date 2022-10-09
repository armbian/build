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

if [[ $(basename "$0") == main.sh ]]; then

	echo "Please use compile.sh to start the build process"
	exit 255

fi

# Libraries include
# shellcheck source=import-functions.sh
source "${SRC}/lib/import-functions.sh"

prepare_and_config_main_build_single

if [[ -z $1 ]]; then
	do_default
else
	eval "$@"
fi
