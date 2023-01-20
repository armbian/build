#!/bin/sh
# echo "DEBUG: postinst: initramfs-clean: cmd: $@" >&2
# avoid running multiple times
# This script should be run after the initramfs-tools script
# and under the same conditions.
if [ -n "$DEB_MAINT_PARAMS" ]; then
	eval set -- "$DEB_MAINT_PARAMS"
	if [ -z "$1" ] || [ "$1" != "configure" ]; then
		exit 0
	fi
fi

files="$(find /boot -maxdepth 1 -name 'initrd.img-*' -o -name 'uInitrd-*')"

for f in $files; do
	if [ ! -d /lib/modules/"${f#*-}" ]; then
		echo "Remove unused generated file: $f"; rm $f
	fi
done

check_boot_dev (){
	available_size_boot_device=$(findmnt --noheadings --output AVAIL --target /boot)
	echo "Free space after deleting the package $DPKG_MAINTSCRIPT_PACKAGE in /boot: $available_size_boot_device" >&2
}
mountpoint -q /boot && check_boot_dev

exit 0
