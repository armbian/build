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

IFS=";"

#OLDFAMILY=""

#START=9
#STOP=9
#BUILD_ALL="demo"

declare -a MYARRAY1=('wheezy' '' 'jessie' '' 'trusty' '');
#declare -a MYARRAY1=('wheezy' '' 'jessie' '' 'trusty' '' 'xenial' '');

# Include here to make "display_alert" and "prepare_host" available
source $SRC/lib/general.sh

# Function display and runs compilation with desired parameters
#
# Two parameters: $1 = BOARD $2 = BRANCH $3 = $TARGET
#
distro-list ()
{

k1=0
l1=1
while [[ $k1 -lt ${#MYARRAY1[@]} ]]
	do
		BUILD_DESKTOP="no"
		BOARD=$1
		RELEASE=${MYARRAY1[$k1]}
		BRANCH=$2
		unset IFS array DESKTOP_TARGET LINUXFAMILY LINUXCONFIG LINUXKERNEL LINUXSOURCE KERNELBRANCH \
		BOOTLOADER BOOTSOURCE BOOTBRANCH CPUMIN GOVERNOR needs_uboot needs_kernel BOOTSIZE UBOOT_TOOLCHAIN KERNEL_TOOLCHAIN

	source $SRC/lib/configuration.sh
 	array=(${DESKTOP_TARGET//,/ })
	arrax=(${CLI_TARGET//,/ })
	
	# % means all BRANCH / DISTRIBUTION
	[[ ${array[0]} == "%" ]] && array[0]=$RELEASE
	[[ ${array[1]} == "%" ]] && array[1]=$2
	[[ ${arrax[0]} == "%" ]] && arrax[0]=$RELEASE
	[[ ${arrax[1]} == "%" ]] && arrax[1]=$2
	
	# we define desktop building in config
	if [[ "$RELEASE" == "${array[0]}" && $2 == "${array[1]}" && $3 == "desktop" ]]; then
			display_alert "$BOARD desktop" "$RELEASE - $BRANCH - $LINUXFAMILY" "ext" 
			BUILD_DESKTOP="yes"
	fi
	
	if [[ "$RELEASE" == "${arrax[0]}" && $2 == "${arrax[1]}" && $3 == "cli" ]]; then
			display_alert "$BOARD CLI" "$RELEASE - $BRANCH - $LINUXFAMILY" "ext" 
			BUILD_DESKTOP="no"
	fi

	# demo - for debugging purposes
	[[ $BUILD_ALL != "demo" ]] && source $SRC/lib/main.sh

	IFS=";"
	k1=$[$k1+2]
	l1=$[$l1+2]
	done
}

IFS=";"
[[ -z "$START" ]] && START=0
MYARRAY=($(cat $SRC/lib/configuration.sh | awk '/)#enabled/ || /#des/ || /#build/' | sed -e 's/\t\t//' | sed 's/)#enabled//g' \
| sed 's/#description //g' | sed -e 's/\t//' | sed 's/#build //g' | sed ':a;N;$!ba;s/\n/;/g'))
i1=$[0+$START]
j1=$[1+$START]
o1=$[2+$START]
while [[ $i1 -lt ${#MYARRAY[@]} ]]
do
	if [[ "${MYARRAY[$o1]}" == "1" || "${MYARRAY[$o1]}" == "3" || "${MYARRAY[$o1]}" == "6" ]]; then 
		distro-list "${MYARRAY[$i1]}" "default" "cli"
		distro-list "${MYARRAY[$i1]}" "default" "desktop"		
		
	fi
	if [[ "${MYARRAY[$o1]}" == "2" || "${MYARRAY[$o1]}" == "3" || "${MYARRAY[$o1]}" == "5" || "${MYARRAY[$o1]}" == "6" ]]; then 
		distro-list "${MYARRAY[$i1]}" "next" "cli" 
		distro-list "${MYARRAY[$i1]}" "next" "desktop"
	fi
	#if [[ "${MYARRAY[$o1]}" == "4" || "${MYARRAY[$o1]}" == "5" || "${MYARRAY[$o1]}" == "6" ]]; then 
	#	distro-list "${MYARRAY[$i1]}" "dev"
	#fi
    i1=$[$i1+3];j1=$[$j1+3];o1=$[$o1+3]
	
	#[[ $BUILD_ALL == "demo" ]] && echo $i1
	if [[ -n "$STOP" && "$i1" -gt "$STOP" ]]; then exit; fi
	
done
