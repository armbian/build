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

# when we want to build from certain start
from=0

RELEASE_LIST=("trusty" "xenial" "wheezy" "jessie")
BRANCH_LIST=("default" "next" "dev")

# add dependencies for converting .md to .pdf
if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
	curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
	apt-get install -y libfontconfig1 nodejs 
	npm install -g markdown-pdf
fi

create_images_list()
{
	for board in $SRC/lib/config/boards/*.conf; do
		BOARD=$(basename $board | cut -d'.' -f1)
		source $SRC/lib/config/boards/$BOARD.conf
		if [[ -n $CLI_TARGET ]]; then

			# RELEASES : BRANCHES
			CLI_TARGET=($(tr ':' ' ' <<< "$CLI_TARGET"))

			build_settings_target=($(tr ',' ' ' <<< "${CLI_TARGET[0]}"))
			build_settings_branch=($(tr ',' ' ' <<< "${CLI_TARGET[1]}"))

			[[ ${build_settings_target[0]} == "%" ]] && build_settings_target[0]="${RELEASE_LIST[@]}"
			[[ ${build_settings_branch[0]} == "%" ]] && build_settings_branch[0]="${BRANCH_LIST[@]}"

			for release in ${build_settings_target[@]}; do
				for kernel in ${build_settings_branch[@]}; do
					buildlist+=("$BOARD $kernel $release no")
				done
			done
		fi
		if [[ -n $DESKTOP_TARGET ]]; then

			# RELEASES : BRANCHES
			DESKTOP_TARGET=($(tr ':' ' ' <<< "$DESKTOP_TARGET"))

			build_settings_target=($(tr ',' ' ' <<< "${DESKTOP_TARGET[0]}"))
			build_settings_branch=($(tr ',' ' ' <<< "${DESKTOP_TARGET[1]}"))

			[[ ${build_settings_target[0]} == "%" ]] && build_settings_target[0]="${RELEASE_LIST[@]}"
			[[ ${build_settings_branch[0]} == "%" ]] && build_settings_branch[0]="${BRANCH_LIST[@]}"

			for release in ${build_settings_target[@]}; do
				for kernel in ${build_settings_branch[@]}; do
					buildlist+=("$BOARD $kernel $release yes")
				done
			done

		fi
		unset CLI_TARGET CLI_BRANCH DESKTOP_TARGET DESKTOP_BRANCH KERNEL_TARGET
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
	printf "%-3s %-20s %-10s %-10s %-10s\n" \#   BOARD BRANCH
else
	create_images_list
	printf "%-3s %-20s %-10s %-10s %-10s\n" \#   BOARD BRANCH RELEASE DESKTOP
fi

n=0
for line in "${buildlist[@]}"; do
	n=$[$n+1]
	printf "%-3s %-20s %-10s %-10s %-10s\n" $n $line
done
echo -e "\n${#buildlist[@]} total\n"

[[ $BUILD_ALL == demo ]] && exit 0

buildall_start=`date +%s`
n=0
for line in "${buildlist[@]}"; do
	unset LINUXFAMILY LINUXCONFIG KERNELDIR KERNELSOURCE KERNELBRANCH BOOTDIR BOOTSOURCE BOOTBRANCH ARCH UBOOT_NEEDS_GCC KERNEL_NEEDS_GCC \
		CPUMIN CPUMAX UBOOT_VER KERNEL_VER GOVERNOR BOOTSIZE UBOOT_TOOLCHAIN KERNEL_TOOLCHAIN PACKAGE_LIST_EXCLUDE KERNEL_IMAGE_TYPE \
		write_uboot_platform family_tweaks install_boot_script UBOOT_FILES LOCALVERSION UBOOT_COMPILER KERNEL_COMPILER UBOOT_TARGET \
		MODULES MODULES_NEXT INITRD_ARCH

	read BOARD BRANCH RELEASE BUILD_DESKTOP <<< $line
	n=$[$n+1]
	if [[ $from -le $n && ! -f "/run/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_$BUILD_DESKTOP.pid" ]]; then
		display_alert "Building $n / ${#buildlist[@]}" "Board: $BOARD Kernel:$BRANCH${RELEASE:+ Release: $RELEASE}${BUILD_DESKTOP:+ Desktop: $BUILD_DESKTOP}" "ext"
		#touch "/run/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_$BUILD_DESKTOP.pid" 
		source $SRC/lib/main.sh
		#rm "/run/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_$BUILD_DESKTOP.pid" 
	fi
done

buildall_end=`date +%s`
buildall_runtime=$(((buildall_end - buildall_start) / 60))
display_alert "Runtime" "$buildall_runtime min" "info"
