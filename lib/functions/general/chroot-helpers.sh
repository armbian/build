#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# mount_chroot <target>
function mount_chroot() {
	if [[ "x${LOG_SECTION}x" == "xx" ]]; then
		display_alert "mount_chroot called outside of logging section..." "mount_chroot '$1'\n$(stack_color="${magenta_color:-}" show_caller_full)" "warn"
	fi

	local target cache_src
	target="$(realpath "$1")" # normalize, remove last slash if dir
	display_alert "mount_chroot" "$target" "debug"
	# Track mounts we create so we can unwind on failure.
	local -a mounted_points=()
	cleanup_mounted_points() {
		local -i i
		for (( i=${#mounted_points[@]}-1; i>=0; i-- )); do
			umount --recursive "${mounted_points[i]}" &> /dev/null || true
		done
	}
	if ! mkdir -p "${target}/run/user/0"; then
		display_alert "Failed to prepare chroot runtime directory" "${target}/run/user/0" "err"
		return 1
	fi

	# tmpfs size=50% is the Linux default, but we need more.
	if ! mountpoint -q "${target}/tmp"; then
		if ! mount -t tmpfs -o "size=99%" tmpfs "${target}/tmp"; then
			display_alert "Failed to mount tmpfs inside chroot" "${target}/tmp" "err"
			cleanup_mounted_points
			return 1
		fi
		mounted_points+=("${target}/tmp")
	fi
	if ! mountpoint -q "${target}/var/tmp"; then
		if ! mount -t tmpfs -o "size=99%" tmpfs "${target}/var/tmp"; then
			display_alert "Failed to mount tmpfs inside chroot" "${target}/var/tmp" "err"
			cleanup_mounted_points
			return 1
		fi
		mounted_points+=("${target}/var/tmp")
	fi
	if ! mountpoint -q "${target}/run/user/0"; then
		if ! mount -t tmpfs -o "size=99%" tmpfs "${target}/run/user/0"; then
			display_alert "Failed to mount tmpfs inside chroot" "${target}/run/user/0" "err"
			cleanup_mounted_points
			return 1
		fi
		mounted_points+=("${target}/run/user/0")
	fi
	if ! mountpoint -q "${target}/proc"; then
		if ! mount -t proc chproc "${target}/proc"; then
			display_alert "Failed to mount proc inside chroot" "${target}/proc" "err"
			cleanup_mounted_points
			return 1
		fi
		mounted_points+=("${target}/proc")
	fi
	if ! mountpoint -q "${target}/sys"; then
		if ! mount -t sysfs chsys "${target}/sys"; then
			display_alert "Failed to mount sysfs inside chroot" "${target}/sys" "err"
			cleanup_mounted_points
			return 1
		fi
		mounted_points+=("${target}/sys")
	fi
	if ! mountpoint -q "${target}/dev"; then
		if ! mount --bind /dev "${target}/dev"; then
			display_alert "Failed to bind /dev into chroot" "${target}/dev" "err"
			cleanup_mounted_points
			return 1
		fi
		mounted_points+=("${target}/dev")
	fi
	if ! mountpoint -q "${target}/dev/pts"; then
		if ! mount -t devpts chpts "${target}/dev/pts" && ! mount --bind /dev/pts "${target}/dev/pts"; then
			display_alert "Failed to mount devpts inside chroot" "${target}/dev/pts" "err"
			cleanup_mounted_points
			return 1
		fi
		mounted_points+=("${target}/dev/pts")
	fi

	# Bind host cache into chroot if present (configurable via ARMBIAN_CACHE_DIR)
	cache_src="${ARMBIAN_CACHE_DIR:-/armbian/cache}"
	if [[ -d "${cache_src}" ]]; then
		if ! mkdir -p "${target}/armbian/cache"; then
			display_alert "Failed to create cache mountpoint" "${target}/armbian/cache" "warn"
		elif mountpoint -q "${target}/armbian/cache"; then
			display_alert "Cache already mounted — skipping cache bind" "${target}/armbian/cache" "debug"
		else
			if ! mount --bind "${cache_src}" "${target}/armbian/cache"; then
				display_alert "Cache bind failed" "${cache_src} -> ${target}/armbian/cache" "warn"
			fi
		fi
	else
		display_alert "Host cache not found — skipping cache mount" "${cache_src}" "warn"
	fi
}

# umount_chroot <target>
function umount_chroot() {
	if [[ "x${LOG_SECTION}x" == "xx" ]]; then
		display_alert "umount_chroot called outside of logging section..." "umount_chroot '$1'\n$(stack_color="${magenta_color:-}" show_caller_full)" "warn"
	fi
	local target
	target="$(realpath "$1")" # normalize, remove last slash if dir
	display_alert "Unmounting" "$target" "info"

	if mountpoint -q "${target}/armbian/cache"; then
		umount "${target}/armbian/cache" || true
	fi

	while grep -Eq "${target}\/(dev|proc|sys|tmp|var\/tmp|run\/user\/0)" /proc/mounts; do
		display_alert "Unmounting..." "target: ${target}" "debug"
		umount "${target}"/dev/pts || true
		umount --recursive "${target}"/dev || true
		umount "${target}"/proc || true
		umount --recursive "${target}"/sys || true
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
