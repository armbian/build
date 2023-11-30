#!/bin/bash

# Copyright (c) 2017 The Armbian Project https://www.armbian.com/
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

if [[ ! -n $1 ]]; then
	echo >&2 "Usage: $0 <overlay_source_file.dts>"
	exit -1
fi

if [[ $EUID -ne 0 ]]; then
	echo >&2 "This program must be run with superuser rights"
	exit -1
fi

if [[ ! -f $1 ]]; then
	echo >&2 "Can't open file $1. File does not exist?"
	exit -1
fi

if [[ $1 == *.dts ]]; then
	fname=$(basename $1 .dts)
else
	echo >&2 "Overlay source file name should have the .dts extension"
	exit -1
fi

if [[ ! -f /etc/armbian-release || ! -f /boot/armbianEnv.txt ]]; then
	echo >&2 "Armbian is not installed properly. Missing armbian-release or armbianEnv.txt"
	exit -1
fi

. /etc/armbian-release

if ! grep -q '^setenv overlay_error' /boot/boot.cmd; then
	echo >&2 "Overlays are not supported on ${LINUXFAMILY^} based boards."
	exit -1
fi

if [[ -d /lib/modules/$(uname -r)/build/scripts/dtc ]]; then
	if [[ ! -x /lib/modules/$(uname -r)/build/scripts/dtc/dtc ]]; then
		# Can't use distribution provided (i.e. Bionic) dtc yet
		# https://git.kernel.org/pub/scm/utils/dtc/dtc.git/commit/livetree.c?id=bba26a5291c8343101e0296b0e478deb4c9b60b0
		echo >&2 "Error: kernel headers are not installed properly"
		echo >&2 "Can't find dtc that supports compiling overlays"
		echo >&2 "Please install the headers package for kernel $(uname -r)"
		exit -1
	else
		export PATH=/lib/modules/$(uname -r)/build/scripts/dtc/:$PATH
	fi
fi

if ! type dtc > /dev/null ; then
	echo "Error: dtc not found in PATH"
	echo "Please try to install matching kernel headers"
	exit -1
fi

if ! grep -q 'symbols' <(dtc --help) ; then
	echo "Error: dtc does not support compiling overlays"
#	echo "Please try to install matching kernel headers"
	exit -1
fi

if [[ ! -d /boot/overlay-user ]]; then
	mkdir -p /boot/overlay-user
fi

temp_dir=$(mktemp -d)

echo "Compiling the overlay"

dtc -@ -q -I dts -O dtb -o ${temp_dir}/${fname}.dtbo $1

if [[ $? -ne 0 ]]; then
	echo >&2 "Error compiling the overlay"
	exit -1
fi

echo "Copying the compiled overlay file to /boot/overlay-user/"
cp ${temp_dir}/${fname}.dtbo /boot/overlay-user/${fname}.dtbo

if grep -q '^user_overlays=' /boot/armbianEnv.txt; then
	line=$(grep '^user_overlays=' /boot/armbianEnv.txt | cut -d'=' -f2)
	if grep -qE "(^|[[:space:]])${fname}([[:space:]]|$)" <<< $line; then
		echo "Overlay ${fname} was already added to /boot/armbianEnv.txt, skipping"
	elif grep -q '^user_overlays=\s*$' /boot/armbianEnv.txt; then
		sed -i -e "s/^user_overlays=\s*$/user_overlays=${fname}/" /boot/armbianEnv.txt
	else
		sed -i -e "/^user_overlays=/ s/$/ ${fname}/" /boot/armbianEnv.txt
	fi
else
	sed -i -e "\$auser_overlays=${fname}" /boot/armbianEnv.txt
fi

echo "Reboot is required to apply the changes"
