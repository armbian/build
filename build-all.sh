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

# Include here to make "display_alert" and "prepare_host" available
source $SRC/lib/general.sh

RELEASE_LIST=("trusty" "xenial" "wheezy" "jessie")

create_images_list()
{
	for board in $SRC/lib/config/boards/*.conf; do
		BOARD=$(basename $board | cut -d'.' -f1)
		source $SRC/lib/config/boards/$BOARD.conf
		if [[ -n $CLI_TARGET ]]; then
			build_settings=($(tr ',' ' ' <<< "$CLI_TARGET"))
			# release
			[[ ${build_settings[0]} == "%" ]] && build_settings[0]="${RELEASE_LIST[@]}"
			# kernel
			# NOTE: This prevents building images with "dev" kernel - may need another solution for sun8i
			[[ ${build_settings[1]} == "%" ]] && build_settings[1]=$(tr ',' ' ' <<< "${KERNEL_TARGET//dev}")
			for release in ${build_settings[0]}; do
				for kernel in ${build_settings[1]}; do
					buildlist+=("$BOARD $kernel $release no")
				done
			done
		fi
		if [[ -n $DESKTOP_TARGET ]]; then
			build_settings=($(tr ',' ' ' <<< "$DESKTOP_TARGET"))
			# release
			[[ ${build_settings[0]} == "%" ]] && build_settings[0]="${RELEASE_LIST[@]}"
			# kernel
			# NOTE: This prevents building images with "dev" kernel - may need another solution for sun8i
			[[ ${build_settings[1]} == "%" ]] && build_settings[1]=$(tr ',' ' ' <<< "${KERNEL_TARGET//dev}")
			for release in ${build_settings[0]}; do
				for kernel in ${build_settings[1]}; do
					buildlist+=("$BOARD $kernel $release yes")
				done
			done
		fi
		unset CLI_TARGET DESKTOP_TARGET KERNEL_TARGET
	done
}

create_kernels_list()
{
	for board in $SRC/lib/config/boards/*.conf; do
		BOARD=$(basename $board | cut -d'.' -f1)
		source $SRC/lib/config/boards/$BOARD.conf
		if [[ -n $KERNEL_TARGET ]]; then
			for kernel in $(tr ',' ' ' <<< $KERNEL_TARGET); do
				buildlist+=("$BOARD $kernel")
			done
		fi
		unset KERNEL_TARGET
	done
}

buildlist=()

if [[ $KERNEL_ONLY == yes ]]; then
	create_kernels_list
	printf "%-20s %-10s %-10s %-10s\n" BOARD BRANCH
else
	create_images_list
	printf "%-20s %-10s %-10s %-10s\n" BOARD BRANCH RELEASE DESKTOP
fi

for line in "${buildlist[@]}"; do
	printf "%-20s %-10s %-10s %-10s\n" $line
done
echo -e "\n${#buildlist[@]} total\n"

[[ $BUILD_ALL == demo ]] && exit 0

buildall_start=`date +%s`

for line in "${buildlist[@]}"; do
	unset IFS LINUXFAMILY LINUXCONFIG LINUXKERNEL LINUXSOURCE KERNELBRANCH BOOTLOADER BOOTSOURCE BOOTBRANCH \
		CPUMIN GOVERNOR NEEDS_UBOOT NEEDS_KERNEL BOOTSIZE UBOOT_TOOLCHAIN KERNEL_TOOLCHAIN
	read BOARD BRANCH RELEASE BUILD_DESKTOP <<< $line
	display_alert "Building" "Board: $BOARD Kernel:$BRANCH${RELEASE:+ Release: $RELEASE}${BUILD_DESKTOP:+ Desktop: $BUILD_DESKTOP}" "ext"
	source $SRC/lib/main.sh
done

buildall_end=`date +%s`
buildall_runtime=$(((buildall_end - buildall_start) / 60))
display_alert "Runtime" "$buildall_runtime min" "info"
