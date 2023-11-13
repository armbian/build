#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# mount_chroot <target>
function mount_chroot() {
	if [[ "x${LOG_SECTION}x" == "xx" ]]; then
		display_alert "mount_chroot called outside of logging section..." "mount_chroot '$1'\n$(stack_color="${magenta_color:-}" show_caller_full)" "warn"
	fi

	local target
	target="$(realpath "$1")" # normalize, remove last slash if dir
	display_alert "mount_chroot" "$target" "debug"
	mkdir -p "${target}/run/user/0"

	# tmpfs size=50% is the Linux default, but we need more.
	mount -t tmpfs -o "size=99%" tmpfs "${target}/tmp"
	mount -t tmpfs -o "size=99%" tmpfs "${target}/var/tmp"
	mount -t tmpfs -o "size=99%" tmpfs "${target}/run/user/0"
	mount -t proc chproc "${target}"/proc
	mount -t sysfs chsys "${target}"/sys
	mount --bind /dev "${target}"/dev
	mount -t devpts chpts "${target}"/dev/pts || mount --bind /dev/pts "${target}"/dev/pts
}

# umount_chroot <target>
function umount_chroot() {
	if [[ "x${LOG_SECTION}x" == "xx" ]]; then
		display_alert "umount_chroot called outside of logging section..." "umount_chroot '$1'\n$(stack_color="${magenta_color:-}" show_caller_full)" "warn"
	fi
	local target
	target="$(realpath "$1")" # normalize, remove last slash if dir
	display_alert "Unmounting" "$target" "info"
	while grep -Eq "${target}\/(dev|proc|sys|tmp|var\/tmp|run\/user\/0)" /proc/mounts; do
		display_alert "Unmounting..." "target: ${target}" "debug"
		umount "${target}"/dev/pts || true
		umount --recursive "${target}"/dev || true
		umount "${target}"/proc || true
		umount "${target}"/sys || true
		umount "${target}"/tmp || true
		umount "${target}"/var/tmp || true
		umount "${target}"/run/user/0 || true
		wait_for_disk_sync "after umount chroot"
		run_host_command_logged grep -E "'${target}/(dev|proc|sys|tmp)'" /proc/mounts "||" true
	done
	run_host_command_logged rm -rf "${target}"/run/user/0
}

# demented recursive version, for final umount. call: umount_chroot_recursive /some/dir "DESCRIPTION"
function umount_chroot_recursive() {
	if [[ ! -d "${1}" ]]; then # only even try if target is a directory
		return 0
	fi

	local target description="${2:-"UNKNOWN"}"
	target="$(realpath "$1")/" # normalize, make sure to have slash as last element

	if [[ ! -d "${target}" ]]; then     # only even try if target is a directory
		return 0                           # success, nothing to do.
	elif [[ "${target}" == "/" ]]; then # make sure we're not trying to umount root itself.
		return 0
	fi
	display_alert "Unmounting recursively" "${description} - be patient" ""
	wait_for_disk_sync "before recursive umount ${description}" # sync. coalesce I/O. wait for writes to flush to disk. it might take a second.
	# First, try to umount some well-known dirs, in a certain order. for speed.
	local -a well_known_list=("dev/pts" "dev" "proc" "sys" "boot/efi" "boot/firmware" "boot" "tmp" ".")
	for well_known in "${well_known_list[@]}"; do
		umount --recursive "${target}${well_known}" &> /dev/null || true # ignore errors
	done

	# now try in a loop to unmount all that's still mounted under the target
	local -i tries=1                                                                              # the first try above
	mapfile -t current_mount_list < <(cut -d " " -f 2 "/proc/mounts" | grep "^${target}" || true) # don't let grep error out.
	while [[ ${#current_mount_list[@]} -gt 0 ]]; do
		if [[ $tries -gt 10 ]]; then
			display_alert "${#current_mount_list[@]} dirs still mounted after ${tries} tries:" "${current_mount_list[*]}" "wrn"
		fi
		cut -d " " -f 2 "/proc/mounts" | grep "^${target}" | xargs -n1 umount --recursive &> /dev/null || true # ignore errors
		wait_for_disk_sync "during recursive umount ${description}"                                            # sync. coalesce I/O. wait for writes to flush to disk. it might take a second.
		mapfile -t current_mount_list < <(cut -d " " -f 2 "/proc/mounts" | grep "^${target}")
		tries=$((tries + 1))
	done

	# if more than one try..
	if [[ $tries -gt 1 ]]; then
		display_alert "Unmounted OK after ${tries} attempt(s)" "${description}" "info"
	fi
	return 0
}
