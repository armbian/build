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
	if [[ "${OSTYPE}" == "darwin"* ]]; then
		echo "Armbian build scripts require brew to be installed and working on macOS. (old Bash version)" >&2
		echo "Please install brew, *restart your terminal*." >&2
		echo "Then run 'brew install bash coreutils git', *restart your terminal* and then try again." >&2
		exit 51
	fi
	exit 50
fi

# If under Darwin, we require brew to be installed and working. Check.
if [[ "${OSTYPE}" == "darwin"* ]]; then
	# Don't allow running as root on macOS.
	if [[ "${EUID}" -eq 0 ]]; then
		echo "Armbian build scripts do not support running as root on macOS." >&2
		echo "Please run as a normal user." >&2
		exit 51
	fi

	if ! command -v brew &> /dev/null; then
		echo "Armbian build scripts require brew to be installed and working on macOS. (brew not available)" >&2
		echo "Please install brew, *restart your terminal*." >&2
		echo "Then run 'brew install bash coreutils git', *restart your terminal* and then try again." >&2
		exit 51
	fi

	# Run "brew --prefix" to check if brew is working.
	if ! brew --prefix &> /dev/null; then
		echo "Armbian build scripts require brew to be installed and working on macOS. (brew --prefix failed)" >&2
		echo "Please install brew, *restart your terminal*." >&2
		echo "Then run 'brew install bash coreutils git', *restart your terminal* and then try again." >&2
		exit 51
	fi

	declare brew_prefix
	brew_prefix="$(brew --prefix)"

	# Make sure realpath is available via brew's coreutils, under ${brew_prefix}
	if ! command -v "${brew_prefix}/opt/coreutils/libexec/gnubin/realpath" &> /dev/null; then
		echo "Armbian build scripts require realpath to be installed via brew's coreutils on macOS. (realpath not available)" >&2
		echo "Please install brew, *restart your terminal*." >&2
		echo "Then run 'brew install bash coreutils git', *restart your terminal* and then try again." >&2
		echo "If that fails, try 'brew reinstall bash coreutils git' and try again." >&2
		exit 51
	fi

	# If under Darwin, we need to set the PATH to include the GNU coreutils.
	# export PATH with new coreutils gnubin's in front.
	export PATH="${brew_prefix}/opt/coreutils/libexec/gnubin:$PATH"
	unset brew_prefix

	# Under Darwin/Docker, the "${SRC}" should be under "${HOME}" -- otherwise Docker will not be able to share/mount it.
	# This is a sanity check to make sure that the user is not trying to build outside of "${HOME}".
	if [[ "${SRC}" != "${HOME}"* ]]; then
		echo "Armbian build scripts require the Armbian directory ($SRC) to be under your home directory ($HOME) on macOS." >&2
		echo "Please clone inside your home directory and try again." >&2
		exit 52
	fi
fi

if [[ -z "$(command -v realpath)" ]]; then
	echo "Armbian build scripts require coreutils. Go install it." >&2
	exit 53
fi

# Users should not start here, but instead use ./compile.sh at the root.
if [[ $(basename "$0") == single.sh ]]; then
	echo "Please use compile.sh to start the build process"
	exit 255
fi

# Libraries include. ONLY source files that contain ONLY functions here.

# shellcheck source=lib/library-functions.sh
source "${SRC}"/lib/library-functions.sh
