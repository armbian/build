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

# The Armbian functions require Bash 5.x.
if [[ "${BASH_VERSINFO:-0}" -lt 5 ]]; then
	echo "Armbian build scripts require Bash 5.x. Go get it..." >&2
	# @TODO: rpardini: add instructions, maybe.
	exit 50
fi

if [[ -z "$(command -v realpath)" ]]; then
	echo "Armbian build scripts require coreutils. Go install it." >&2
	exit 51
fi

# Users should not start here, but instead use ./compile.sh at the root.
if [[ $(basename "$0") == single.sh ]]; then
	echo "Please use compile.sh to start the build process"
	exit 255
fi

# Libraries include. ONLY source files that contain ONLY functions here.

# shellcheck source=lib/library-functions.sh
source "${SRC}"/lib/library-functions.sh
