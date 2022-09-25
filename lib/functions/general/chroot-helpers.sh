#!/usr/bin/env bash
# mount_chroot <target>
#
# helper to reduce code duplication
#
mount_chroot() {
	local target
	target="$(realpath "$1")" # normalize, remove last slash if dir
	display_alert "mount_chroot" "$target" "debug"
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
	local target
	target="$(realpath "$1")" # normalize, remove last slash if dir
	display_alert "Unmounting" "$target" "info"
	while grep -Eq "${target}\/(dev|proc|sys|tmp)" /proc/mounts; do
		display_alert "Unmounting..." "target: ${target}" "debug"
		umount "${target}"/dev/pts || true
		umount --recursive "${target}"/dev || true
		umount "${target}"/proc || true
		umount "${target}"/sys || true
		umount "${target}"/tmp || true
		sync
		run_host_command_logged grep -E "'${target}/(dev|proc|sys|tmp)'" /proc/mounts "||" true
	done
}

# demented recursive version, for final umount.
function umount_chroot_recursive() {
	local target
	target="$(realpath "$1")/" # normalize, make sure to have slash as last element

	if [[ ! -d "${target}" ]]; then     # only even try if target is a directory
		return 0                           # success, nothing to do.
	elif [[ "${target}" == "/" ]]; then # make sure we're not trying to umount root itself.
		return 0
	fi
	display_alert "Unmounting recursively" "${target}" ""
	sync # sync. coalesce I/O. wait for writes to flush to disk. it might take a second.
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
		sync                                                                                                   # wait for fsync, then count again for next loop.
		mapfile -t current_mount_list < <(cut -d " " -f 2 "/proc/mounts" | grep "^${target}")
		tries=$((tries + 1))
	done

	display_alert "Unmounted OK after ${tries} attempt(s)" "$target" "info"
	return 0
}
