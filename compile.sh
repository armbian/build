#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#
#--------------------------------------------------------------------------------------------------------------------------------

# Read build script documentation http://www.armbian.com/using-armbian-tools/
# for detailed explanation of these options and for additional options not listed here

KERNEL_ONLY=""				# leave empty to select each time, set to "yes" or "no" to skip dialog prompt
KERNEL_CONFIGURE="no"			# change provided kernel configuration
CLEAN_LEVEL="make,debs,oldcache"	# comma-separated list of clean targets: "make" = make clean for selected kernel and u-boot,
					# "debs" = delete packages in "./output/debs" for current branch and family,
					# "alldebs" = delete all packages in "./output/debs", "images" = delete "./output/images",
					# "cache" = delete "./output/cache", "sources" = delete "./sources"
					# "oldcache" = remove old cached rootfs except for the newest 6 files

DEST_LANG="en_US.UTF-8"			# sl_SI.UTF-8, en_US.UTF-8

# advanced
KERNEL_KEEP_CONFIG="no"			# do not overwrite kernel config before compilation
EXTERNAL="yes"				# build and install extra applications and drivers
EXTERNAL_NEW="prebuilt"			# compile and install or install prebuilt additional packages
CREATE_PATCHES="no"			# wait that you make changes to uboot and kernel source and creates patches
FORCE_CHECKOUT="yes"			# ignore manual changes to source
BUILD_ALL="no"				# cycle through available boards and make images or kernel/u-boot packages.
					# set KERNEL_ONLY to "yes" or "no" to build all packages/all images

BETA=""					# set yes to add subrevision with tomorrow's date. For internal use.
MULTITHREAD=""				# build n images at once. For internal use.

# build script version to use
LIB_TAG=""				# empty for latest version,
					# one of listed here: https://github.com/igorpecovnik/lib/tags for stable versions,
					# or commit hash
#--------------------------------------------------------------------------------------------------------------------------------

# source is where compile.sh is located
SRC=$(pwd)

#--------------------------------------------------------------------------------------------------------------------------------
# To preserve proper libraries updating
#--------------------------------------------------------------------------------------------------------------------------------
if [[ -f $SRC/main.sh && -d $SRC/bin ]]; then
	echo -e "[\e[0;31m error \x1B[0m] Copy this file one level up, alter and run again."
	exit -1
fi

if [[ $EUID != 0 ]]; then
	echo -e "[\e[0;35m warn \x1B[0m] This script requires root privileges"
	sudo "$0" "$@"
	exit $?
fi

#--------------------------------------------------------------------------------------------------------------------------------
# Get updates of the main build libraries
#--------------------------------------------------------------------------------------------------------------------------------
[[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' git 2>/dev/null) != *ii* ]] && \
	apt-get -qq -y --no-install-recommends install git

if [[ ! -d $SRC/lib ]]; then
	git clone https://github.com/igorpecovnik/lib
fi
cd $SRC/lib
if [[ ! -f $SRC/.ignore_changes ]]; then
	echo -e "[\e[0;32m o.k. \x1B[0m] This script will try to update"
	git pull
	CHANGED_FILES=$(git diff --name-only)
	if [[ -n $CHANGED_FILES ]]; then
		echo -e "[\e[0;35m warn \x1B[0m] Can't update since you made changes to: \e[0;32m\n${CHANGED_FILES}\x1B[0m"
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read
	else
		git checkout ${LIB_TAG:- master}
	fi
fi

# source additional configuration file
[[ -n $1 && -f $SRC/config-$1.conf ]] && source $SRC/config-$1.conf

# daily beta build contains date in subrevision
if [[ $BETA == yes ]]; then SUBREVISION="."$(date --date="tomorrow" +"%y%m%d"); fi

if [[ $BUILD_ALL == yes || $BUILD_ALL == demo ]]; then
	source $SRC/lib/build-all.sh
else
	source $SRC/lib/main.sh
fi

# hook for function to run after build, i.e. to change owner of $SRC
# NOTE: this will run only if there were no errors during build process
[[ $(type -t run_after_build) == function ]] && run_after_build || true

# If you are committing new version of this file, increment VERSION
# Only integers are supported
# VERSION=25
