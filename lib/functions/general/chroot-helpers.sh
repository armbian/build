#!/usr/bin/env bash
# mount_chroot <target>
#
# helper to reduce code duplication
#
mount_chroot() {

	local target=$1
	mount -t tmpfs tmpfs "${target}/tmp"
	mount -t proc chproc "${target}"/proc
	mount -t sysfs chsys "${target}"/sys
	mount -t devtmpfs chdev "${target}"/dev || mount --bind /dev "${target}"/dev
	mount -t devpts chpts "${target}"/dev/pts

}

# umount_chroot <target>
#
# helper to reduce code duplication
#
umount_chroot() {

	local target=$1
	display_alert "Unmounting" "$target" "info"
	while grep -Eq "${target}/*(dev|proc|sys|tmp)" /proc/mounts; do
		umount -l --recursive "${target}"/dev > /dev/null 2>&1
		umount -l "${target}"/proc > /dev/null 2>&1
		umount -l "${target}"/sys > /dev/null 2>&1
		umount -l "${target}"/tmp > /dev/null 2>&1
		sleep 5
	done

}
