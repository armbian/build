# unmount_on_exit - used during rootfs building, to avoid leaving mounted stuff behind
#
unmount_on_exit() {
	set +e               # we just wanna plow through this, ignoring errors.
	trap - INT TERM EXIT # remove the trap

	local stack_here
	stack_here="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}" || true)"
	display_alert "trap caught, shutting down" "${stack_here}" "err"
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
		exit_with_error "generic error during build_rootfs_image: ${stack_here}" || true # but don't trigger error again
	fi

	return 49 # trap returns error.
}

# added by main_default_build_single to show details about errors when they happen and exit. exit might trigger the above.
function main_error_monitor() {
	if [[ "${ALREADY_EXITING_WITH_ERROR}" == "yes" ]]; then
		display_alert "second run detected" "ERR trap" "err"
		#exit 46
	fi
	#trap - ERR # remove this trap
	local errcode="${1}"
	# If there's no error, do nothing.
	if [[ $errcode -eq 0 ]]; then
		return 0
	fi
	local stack_caller="${2}"
	local full_stack_caller="${3}"
	if [[ "${ALREADY_EXITING_WITH_ERROR}" != "yes" ]]; then # Don't do this is exit_with_error already did it.
		local logfile_to_show="${CURRENT_LOGFILE}"             # store it
		unset CURRENT_LOGFILE                                  # stop logging, otherwise crazy
		logging_error_show_log "main_error_monitor unknown error" "main_error_monitor unknown highlight" "${stack_caller}" "${logfile_to_show}"
	fi
	display_alert "main_error_monitor: ${errcode}! stack:" "${stack_caller}" "err"
	display_alert "main_error_monitor: ${errcode}! full:" "${full_stack_caller}" "err"

	ALREADY_EXITING_WITH_ERROR=yes
	exit 45
	return 44
}
