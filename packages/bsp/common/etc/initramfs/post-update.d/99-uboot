#!/bin/sh -e

. /etc/armbian-release

tempname="/boot/uInitrd-$1"
echo "update-initramfs: Armbian: Converting to u-boot format: ${tempname}" >&2
mkimage -A $INITRD_ARCH -O linux -T ramdisk -C gzip -n uInitrd -d $2 $tempname

echo "update-initramfs: Armbian: Symlinking ${tempname} to /boot/uInitrd" >&2
ln -sfv $(basename $tempname) /boot/uInitrd || {
	echo "update-initramfs: Symlink failed, moving ${tempname} to /boot/uInitrd" >&2
	mv -v $tempname /boot/uInitrd
}

echo "update-initramfs: Armbian: done." >&2

exit 0
