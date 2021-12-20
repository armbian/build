# mount_chroot <target>
#
# helper to reduce code duplication
#
mount_chroot() {

	local target=$1
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
	while grep -Eq "${target}.*(dev|proc|sys)" /proc/mounts; do
		umount --recursive "${target}"/dev > /dev/null 2>&1 || true
		umount "${target}"/proc > /dev/null 2>&1 || true
		umount "${target}"/sys > /dev/null 2>&1 || true
		sync
	done
}

# demented recursive version, for final umount.
umount_chroot_recursive() {
	set +e # really, ignore errors. we wanna unmount everything and will try very hard.
	local target="$1"

	if [[ ! -d "${target}" ]]; then # only even try if target is a directory
		return 0                       # success, nothing to do.
	fi
	display_alert "Unmounting recursively" "$target" ""
	sync # sync. coalesce I/O. wait for writes to flush to disk. it might take a second.
	# First, try to umount some well-known dirs, in a certain order. for speed.
	local -a well_known_list=("dev/pts" "dev" "proc" "sys" "boot/efi" "boot/firmware" "boot" "tmp" ".")
	for well_known in "${well_known_list[@]}"; do
		umount --recursive "${target}${well_known}" &> /dev/null && sync
	done

	# now try in a loop to unmount all that's still mounted under the target
	local -i tries=1 # the first try above
	mapfile -t current_mount_list < <(cut -d " " -f 2 "/proc/mounts" | grep "^${target}")
	while [[ ${#current_mount_list[@]} -gt 0 ]]; do
		if [[ $tries -gt 10 ]]; then
			display_alert "${#current_mount_list[@]} dirs still mounted after ${tries} tries:" "${current_mount_list[*]}" "wrn"
		fi
		cut -d " " -f 2 "/proc/mounts" | grep "^${target}" | xargs -n1 umount --recursive &> /dev/null
		sync # wait for fsync, then count again for next loop.
		mapfile -t current_mount_list < <(cut -d " " -f 2 "/proc/mounts" | grep "^${target}")
		tries=$((tries + 1))
	done

	display_alert "Unmounted OK after ${tries} attempt(s)" "$target" "info"
	return 0
}
