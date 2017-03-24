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
#
# Main program
#

# destination
DEST=$SRC/output
# sources for compilation
SOURCES=$SRC/sources

TTY_X=$(($(stty size | awk '{print $2}')-6)) # determine terminal width
TTY_Y=$(($(stty size | awk '{print $1}')-6)) # determine terminal height

# We'll use this title on all menus
backtitle="Armbian building script, http://www.armbian.com | Author: Igor Pecovnik"

# if language not set, set to english
[[ -z $LANGUAGE ]] && export LANGUAGE="en_US:en"

# default console if not set
[[ -z $CONSOLE_CHAR ]] && export CONSOLE_CHAR="UTF-8"

# Load libraries
source $SRC/lib/debootstrap-ng.sh 			# System specific install
source $SRC/lib/distributions.sh 			# System specific install
source $SRC/lib/desktop.sh 				# Desktop specific install
source $SRC/lib/common.sh 				# Functions
source $SRC/lib/makeboarddeb.sh 			# Create board support package
source $SRC/lib/general.sh				# General functions
source $SRC/lib/chroot-buildpackages.sh			# Building packages in chroot

# compress and remove old logs
mkdir -p $DEST/debug
(cd $DEST/debug && tar -czf logs-$(<timestamp).tgz *.log) > /dev/null 2>&1
rm -f $DEST/debug/*.log > /dev/null 2>&1
date +"%d_%m_%Y-%H_%M_%S" > $DEST/debug/timestamp
# delete compressed logs older than 7 days
(cd $DEST/debug && find . -name '*.tgz' -atime +7 -delete) > /dev/null

# compile.sh version checking
ver1=$(awk -F"=" '/^# VERSION/ {print $2}' <$SRC/compile.sh )
ver2=$(awk -F"=" '/^# VERSION/ {print $2}' <$SRC/lib/compile.sh 2>/dev/null) || ver2=0
if [[ $BETA != yes && ( -z $ver1 || $ver1 -lt $ver2 ) ]]; then
	display_alert "File $0 is outdated. Please overwrite it with an updated version from" "$SRC/lib" "wrn"
	echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
	read
fi

# Script parameters handling
for i in "$@"; do
	if [[ $i == *=* ]]; then
		parameter=${i%%=*}
		value=${i##*=}
		display_alert "Command line: setting $parameter to" "${value:-(empty)}" "info"
		eval $parameter=$value
	fi
done

if [[ $BETA == yes ]]; then
	IMAGE_TYPE=nightly
else
	IMAGE_TYPE=stable
fi

if [[ $PROGRESS_DISPLAY == none ]]; then
	OUTPUT_VERYSILENT=yes
elif [[ $PROGRESS_DISPLAY != plain ]]; then
	OUTPUT_DIALOG=yes
fi
if [[ $PROGRESS_LOG_TO_FILE != yes ]]; then unset PROGRESS_LOG_TO_FILE; fi

if [[ $USE_CCACHE != no ]]; then
	CCACHE=ccache
	export PATH="/usr/lib/ccache:$PATH"
	# private ccache directory to avoid permission issues when using build script with "sudo"
	# see https://ccache.samba.org/manual.html#_sharing_a_cache for alternative solution
	[[ $PRIVATE_CCACHE == yes ]] && export CCACHE_DIR=$DEST/ccache
else
	CCACHE=""
fi

# optimize build time with 100% CPU usage
CPUS=$(grep -c 'processor' /proc/cpuinfo)
if [[ $USEALLCORES != no ]]; then
	CTHREADS="-j$(($CPUS + $CPUS/2))"
else
	CTHREADS="-j1"
fi

# Check and install dependencies, directory structure and settings
prepare_host

# if KERNEL_ONLY, BOARD, BRANCH or RELEASE are not set, display selection menu

if [[ -z $KERNEL_ONLY ]]; then
	options+=("yes" "Kernel and u-boot packages")
	options+=("no" "OS image for installation to SD card")
	KERNEL_ONLY=$(dialog --stdout --title "Choose an option" --backtitle "$backtitle" --no-tags --menu "Select what to build" \
		$TTY_Y $TTY_X $(($TTY_Y - 8)) "${options[@]}")
	unset options
	[[ -z $KERNEL_ONLY ]] && exit_with_error "No option selected"
fi

EXT='conf'
if [[ -z $BOARD ]]; then
	WIP_STATE='supported'
	WIP_BUTTON='WIP'
	[[ -n $(find $SRC/lib/config/boards/ -name '*.wip' -print -quit) ]] && DIALOG_EXTRA="--extra-button"
	while true; do
		options=()
		for board in $SRC/lib/config/boards/*.${EXT}; do
			options+=("$(basename $board | cut -d'.' -f1)" "$(head -1 $board | cut -d'#' -f2)")
		done
		BOARD=$(dialog --stdout --title "Choose a board" --backtitle "$backtitle" --scrollbar --extra-label "Show $WIP_BUTTON" $DIALOG_EXTRA \
			--menu "Select the target board\nDisplaying $WIP_STATE boards" $TTY_Y $TTY_X $(($TTY_Y - 8)) "${options[@]}")
		STATUS=$?
		if [[ $STATUS == 3 ]]; then
			if [[ $WIP_STATE == supported ]]; then
				WIP_STATE='work-in-progress'
				EXT='wip'
				WIP_BUTTON='supported'
			else
				WIP_STATE='supported'
				EXT='conf'
				WIP_BUTTON='WIP'
			fi
			continue
		elif [[ $STATUS == 0 ]]; then
			break
		fi
		unset options
		[[ -z $BOARD ]] && exit_with_error "No board selected"
	done
fi

if [[ -f $SRC/lib/config/boards/${BOARD}.${EXT} ]]; then
	source $SRC/lib/config/boards/${BOARD}.${EXT}
elif [[ -f $SRC/lib/config/boards/${BOARD}.wip ]]; then
	# when launching build for WIP board from command line
	source $SRC/lib/config/boards/${BOARD}.wip
fi

[[ -z $KERNEL_TARGET ]] && exit_with_error "Board configuration does not define valid kernel config"

if [[ -z $BRANCH ]]; then
	options=()
	[[ $KERNEL_TARGET == *default* ]] && options+=("default" "Vendor provided / legacy (3.4.x - 4.4.x)")
	[[ $KERNEL_TARGET == *next* ]] && options+=("next"       "Mainline (@kernel.org)   (4.x)")
	[[ $KERNEL_TARGET == *dev* ]] && options+=("dev"         "Development version      (4.x)")
	# do not display selection dialog if only one kernel branch is available
	if [[ "${#options[@]}" == 2 ]]; then
		BRANCH="${options[0]}"
	else
		BRANCH=$(dialog --stdout --title "Choose a kernel" --backtitle "$backtitle" \
			--menu "Select the target kernel branch\nExact kernel versions depend on selected board" \
			$TTY_Y $TTY_X $(($TTY_Y - 8)) "${options[@]}")
	fi
	unset options
	[[ -z $BRANCH ]] && exit_with_error "No kernel branch selected"
else
	[[ $KERNEL_TARGET != *$BRANCH* ]] && exit_with_error "Kernel branch not defined for this board" "$BRANCH"
fi

if [[ $KERNEL_ONLY != yes && -z $RELEASE ]]; then
	options=()
	options+=("jessie" "Debian 8 Jessie")
	options+=("xenial" "Ubuntu Xenial 16.04 LTS")
	RELEASE=$(dialog --stdout --title "Choose a release" --backtitle "$backtitle" --menu "Select the target OS release" \
		$TTY_Y $TTY_X $(($TTY_Y - 8)) "${options[@]}")
	unset options
	[[ -z $RELEASE ]] && exit_with_error "No release selected"
fi

if [[ $KERNEL_ONLY != yes && -z $BUILD_DESKTOP ]]; then
	options=()
	options+=("no" "Image with console interface (server)")
	options+=("yes" "Image with desktop environment")
	BUILD_DESKTOP=$(dialog --stdout --title "Choose image type" --backtitle "$backtitle" --no-tags --menu "Select the target image type" \
		$TTY_Y $TTY_X $(($TTY_Y - 8)) "${options[@]}")
	unset options
	[[ -z $BUILD_DESKTOP ]] && exit_with_error "No option selected"
fi

source $SRC/lib/configuration.sh

# sync clock
if [[ $SYNC_CLOCK != no ]]; then
	display_alert "Syncing clock" "host" "info"
	ntpdate -s ${NTP_SERVER:- time.ijs.si}
fi
start=`date +%s`

[[ $CLEAN_LEVEL == *sources* ]] && cleaning "sources"

# ignore updates help on building all images - for internal purposes
# fetch_from_repo <url> <dir> <ref> <subdir_flag>
if [[ $IGNORE_UPDATES != yes ]]; then
	display_alert "Downloading sources" "" "info"
	fetch_from_repo "$BOOTSOURCE" "$BOOTDIR" "$BOOTBRANCH" "yes"
	BOOTSOURCEDIR=$BOOTDIR/${BOOTBRANCH##*:}
	fetch_from_repo "$KERNELSOURCE" "$KERNELDIR" "$KERNELBRANCH" "yes"
	LINUXSOURCEDIR=$KERNELDIR/${KERNELBRANCH##*:}
fi

compile_sunxi_tools

# Here we want to rename LINUXFAMILY from sun4i, sun5i, etc for next and dev branches
# except for sun8i-dev which is separate from sunxi-dev
if [[ $LINUXFAMILY == sun*i && $BRANCH != default ]]; then
    [[ ! ( $LINUXFAMILY == sun8i && $BRANCH == dev ) ]] && LINUXFAMILY="sunxi"
fi

# define package names
DEB_BRANCH=${BRANCH//default}
# if not empty, append hyphen
DEB_BRANCH=${DEB_BRANCH:+${DEB_BRANCH}-}
CHOSEN_UBOOT=linux-u-boot-${DEB_BRANCH}${BOARD}
CHOSEN_KERNEL=linux-image-${DEB_BRANCH}${LINUXFAMILY}
CHOSEN_ROOTFS=linux-${RELEASE}-root-${DEB_BRANCH}${BOARD}

for option in $(tr ',' ' ' <<< "$CLEAN_LEVEL"); do
	[[ $option != sources ]] && cleaning "$option"
done

# Compile u-boot if packed .deb does not exist
if [[ ! -f $DEST/debs/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb ]]; then
	compile_uboot
fi

# Compile kernel if packed .deb does not exist
if [[ ! -f $DEST/debs/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb ]]; then
	compile_kernel
fi

overlayfs_wrapper "cleanup"

# extract kernel version from .deb package
VER=$(dpkg --info $DEST/debs/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb | grep Descr | awk '{print $(NF)}')
VER="${VER/-$LINUXFAMILY/}"

# create board support package
[[ -n $RELEASE && ! -f $DEST/debs/$RELEASE/${CHOSEN_ROOTFS}_${REVISION}_${ARCH}.deb ]] && create_board_package

# build additional packages
[[ $EXTERNAL_NEW == compile ]] && chroot_build_packages

if [[ $KERNEL_ONLY != yes ]]; then
	debootstrap_ng
else
	display_alert "Kernel build done" "@host" "info"
	display_alert "Target directory" "$DEST/debs/" "info"
	display_alert "File name" "${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb" "info"
fi

end=`date +%s`
runtime=$(((end-start)/60))
display_alert "Runtime" "$runtime min" "info"