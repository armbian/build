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
START=0
OLDFAMILY=""
#BUILD_ALL="demo"

# vaid options for automatic building and menu selection
#
# build 0 = don't build
# build 1 = old kernel
# build 2 = next kernel
# build 3 = both kernels
# build 4 = dev kernel
# build 5 = next and dev kernels
# build 6 = legacy and next and dev kernel

distro-list ()
{
declare -a MYARRAY1=('wheezy' 'Debian 7 Wheezy | oldstable' 'jessie' 'Debian 8 Jessie | stable' 'trusty' 'Ubuntu Trusty Tahr 14.04.x LTS');
k1=0
l1=1
while [[ $k1 -lt ${#MYARRAY1[@]} ]]
	do
		BUILD_DESKTOP="no"
		BOARD=$1
		RELEASE=${MYARRAY1[$k1]}
		BRANCH=$2
		if [[ $2 == "default"  && "$RELEASE" == "trusty" ]]; then 
			BUILD_DESKTOP="yes"
		else
			BUILD_DESKTOP="no"
		fi
	unset IFS
	source $SRC/lib/configuration.sh
	if [[ $KERNEL_ONLY == "yes" ]]; then
		if [[ "$OLDFAMILY" != *"$LINUXFAMILY$BRANCH"* ]]; then
		echo "$BOARD $RELEASE $BRANCH $BUILD_DESKTOP $LINUXFAMILY"
		[[ $BUILD_ALL != "demo" ]] && source $SRC/lib/main.sh
		OLDFAMILY=$OLDFAMILY"$LINUXFAMILY$BRANCH"
		fi
	else
		echo "$BOARD $RELEASE $BRANCH $BUILD_DESKTOP $LINUXFAMILY"
		[[ $BUILD_ALL != "demo" ]] && source $SRC/lib/main.sh
	fi # kernel only
	IFS=";"
	
	    k1=$[$k1+2]
		l1=$[$l1+2]
	done
}

IFS=";"

MYARRAY=($(cat $SRC/lib/configuration.sh | awk '/)#enabled/ || /#des/ || /#build/' | sed -e 's/\t\t//' | sed 's/)#enabled//g' | sed 's/#description //g' | sed -e 's/\t//' | sed 's/#build //g' | sed ':a;N;$!ba;s/\n/;/g'))
	i1=$[0+$START]
	j1=$[1+$START]
	o1=$[2+$START]
	while [[ $i1 -lt ${#MYARRAY[@]} ]]
	do
		
		if [[ "${MYARRAY[$o1]}" == "1" || "${MYARRAY[$o1]}" == "3" || "${MYARRAY[$o1]}" == "6" ]]; then 
			distro-list "${MYARRAY[$i1]}" "default"
		fi
		if [[ "${MYARRAY[$o1]}" == "2" || "${MYARRAY[$o1]}" == "3" || "${MYARRAY[$o1]}" == "5" || "${MYARRAY[$o1]}" == "6" ]]; then 
			distro-list "${MYARRAY[$i1]}" "next"
		fi
		if [[ "${MYARRAY[$o1]}" == "4" || "${MYARRAY[$o1]}" == "5" || "${MYARRAY[$o1]}" == "6" ]]; then 
			distro-list "${MYARRAY[$i1]}" "dev"
		fi
		
        i1=$[$i1+3];j1=$[$j1+3];o1=$[$o1+3]
	done
