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

# Ubuntu 26.04 (resolute) and newer ship uutils coreutils. Their rustix-based
# startup reads the process auxiliary vector; when the kernel's primary auxv
# path fails (observed on arm64 vendor/BSP kernels, e.g. Rockchip RK3588) rustix
# falls back to reading /proc/self/auxv. Inside a bare chroot that file does not
# exist, so the binary panics ("called \`Result::unwrap()\` on an \`Err\` value")
# and aborts the very first chroot command run against a freshly-extracted
# rootfs. qemu-user cross-builds are immune (qemu supplies the auxv directly),
# so this only bites *native* builds, where the framework skips qemu entirely.
#
# mount_chroot_proc_for_uutils mounts procfs into the target for a chroot that
# runs before the normal mount_chroot() has set the mounts up. It is a no-op
# when procfs is already present (guarded on ${target}/proc/self/auxv), so it
# stays inert in every stage/build where mount_chroot() already ran. Teardown is
# registered with the cleanup-handler registry so the mount is removed even if a
# later step aborts before the paired done_with_chroot_proc_for_uutils() runs.
# Mirrors the prepare/done idiom in host/mktemp-utils.sh.
#
# mount_chroot_proc_for_uutils <target> <cleanup_id_nameref>
function mount_chroot_proc_for_uutils() {
	local target target_proc
	target="$(realpath "$1")" # normalize, remove last slash if dir
	target_proc="${target}/proc"
	local -n nameref_cleanup_id="${2}" # nameref: set to the cleanup id (empty if nothing mounted)
	nameref_cleanup_id=""

	# procfs already usable? later stages (after mount_chroot) land here -> nothing to do.
	if [[ -e "${target_proc}/self/auxv" ]]; then
		display_alert "procfs already present in chroot" "${target} - uutils workaround not needed" "debug"
		return 0
	fi

	# @Q-quote the path: run_host_command_logged re-parses its args through `bash -c "$*"`,
	# so an unquoted path with whitespace/metacharacters would be word-split a second time.
	display_alert "Mounting procfs for uutils coreutils" "${target} (rustix auxv workaround)" "info"
	run_host_command_logged mkdir -p "${target_proc@Q}"
	run_host_command_logged mount -t proc chproc "${target_proc@Q}"

	# Register teardown so the mount is removed even if a later chroot step aborts.
	nameref_cleanup_id="umount_chroot_proc_for_uutils ${target@Q}"
	add_cleanup_handler "${nameref_cleanup_id}"
	return 0
}

# done_with_chroot_proc_for_uutils <cleanup_id>
# Success-path teardown: unmount now and de-stack the handler. If something fails
# _before_ this, the trap manager runs the registered handler instead.
function done_with_chroot_proc_for_uutils() {
	local cleanup_id="${1}"
	[[ -z "${cleanup_id}" ]] && return 0 # nothing was mounted (procfs already present)
	execute_and_remove_cleanup_handler "${cleanup_id}"
}

# umount_chroot_proc_for_uutils <target> -- cleanup callback; only registered when we mounted.
function umount_chroot_proc_for_uutils() {
	local target="${1}"
	local target_proc="${target}/proc"
	if mountpoint -q "${target_proc}" 2> /dev/null; then
		display_alert "Unmounting procfs mounted for uutils coreutils" "${target}" "debug"
		run_host_command_logged umount "${target_proc@Q}" "||" true
	fi
	return 0
}
