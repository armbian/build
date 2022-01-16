# unmount_on_exit - used during rootfs building, to avoid leaving mounted stuff behind
#
unmount_on_exit() {
	trap - ERR           # Also remove any error trap. it's too late for that.
	set +e               # we just wanna plow through this, ignoring errors.
	trap - INT TERM EXIT # remove the trap

	local stacktrace
	stacktrace="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"
	display_alert "trap caught, shutting down" "${stacktrace}" "err"
	if [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
		ERROR_DEBUG_SHELL=no # dont do it twice
		display_alert "MOUNT" "${MOUNT}" "err"
		display_alert "SDCARD" "${SDCARD}" "err"
		display_alert "ERROR_DEBUG_SHELL=yes, starting a shell." "ERROR_DEBUG_SHELL" "err"
		bash < /dev/tty >&2 || true
	fi

	cd "${SRC}" || echo "Failed to cwd to ${SRC}" # Move pwd away, so unmounts work
	# those will loop until they're unmounted.
	umount_chroot_recursive "${SDCARD}/"
	umount_chroot_recursive "${MOUNT}/"

	mountpoint -q "${SRC}"/cache/toolchain && umount -l "${SRC}"/cache/toolchain >&2 # @TODO: why does Igor uses lazy umounts? nfs?
	mountpoint -q "${SRC}"/cache/rootfs && umount -l "${SRC}"/cache/rootfs >&2
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose "${ROOT_MAPPER}" >&2

	# shellcheck disable=SC2153 # global var. also a local 'loop' in another function. sorry.
	if [[ -b "${LOOP}" ]]; then
		display_alert "Freeing loop" "unmount_on_exit ${LOOP}" "wrn"
		losetup -d "${LOOP}" >&2
	fi

	[[ -d "${SDCARD}" ]] && rm -rf --one-file-system "${SDCARD}"
	[[ -d "${MOUNT}" ]] && rm -rf --one-file-system "${MOUNT}"

	# if we've been called by exit_with_error itself, don't recurse.
	if [[ "${ALREADY_EXITING_WITH_ERROR:-no}" != "yes" ]]; then
		exit_with_error "generic error during build_rootfs_image: ${stacktrace}" || true # but don't trigger error again
	fi

	return 47 # trap returns error. # exit successfully. we're already handling a trap here.
}

# added by main_default_build_single to show details about errors when they happen and exit. exit might trigger the above.
function main_error_monitor() {
	trap - ERR # remove this trap
	local stacktrace
	stacktrace="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}" || true)"
	display_alert "main_error_monitor! '$*'" "${stacktrace}" "err"
	show_caller_full >&2 || true
	display_alert "main_error_monitor2! '$*'" "${stacktrace}" "err"
	exit 46
}
