# Call: prepare_tmpfs_for "NAME_OF_TMPFS_DIR" "${PATH_TO_DIR}" # this adds its own cleanup handler
function prepare_tmpfs_for() {
	declare tmpfs_name="${1}"
	declare tmpfs_path="${2}"
	# validate parameters
	if [[ -z "${tmpfs_name}" ]]; then
		exit_with_error "prepare_tmpfs_for: tmpfs_name (arg 1) is empty"
	fi
	if [[ -z "${tmpfs_path}" ]]; then
		exit_with_error "prepare_tmpfs_for: tmpfs_path (arg 2) is empty"
	fi

	# params for the handler; initially just repeat our own params
	declare -a cleanup_params=("${tmpfs_name}" "${tmpfs_path}")

	# create the dir if not exists and note that down for the cleanup handler
	if [[ ! -d "${tmpfs_path}" ]]; then
		display_alert "prepare_tmpfs_for: creating dir" "${tmpfs_path}" "cleanup"
		mkdir -p "${tmpfs_path}"
		cleanup_params+=("remove_dir")
	else
		display_alert "prepare_tmpfs_for: dir exists" "${tmpfs_path}" "cleanup"
		cleanup_params+=("no_remove_dir")
	fi

	# Do nothing if we're not on Linux (detect via OSTYPE) and root. Still, setup the cleanup handler.
	if [[ "${OSTYPE}" != "linux"* ]] || [[ "${EUID}" -ne 0 ]]; then
		display_alert "prepare_tmpfs_for: not on Linux or not root, skipping" "${tmpfs_name}" "cleanup"
		cleanup_params+=("no_umount_tmpfs")
	elif [[ "${ARMBIAN_INSIDE_DOCKERFILE_BUILD}" == "yes" ]]; then
		display_alert "prepare_tmpfs_for: inside Dockerfile build, skipping" "${tmpfs_name}" "cleanup"
		cleanup_params+=("no_umount_tmpfs")
	else
		display_alert "prepare_tmpfs_for: on Linux and root, MOUNTING TMPFS" "${tmpfs_name}" "cleanup"
		# mount tmpfs on it
		mount -t tmpfs tmpfs "${tmpfs_path}"
		cleanup_params+=("umount_tmpfs")

		#cleanup_params+=("no_umount_tmpfs")
	fi

	# add the cleanup handler
	declare cleanup_handler="cleanup_tmpfs_for ${cleanup_params[*]@Q}"
	display_alert "prepare_tmpfs_for: add cleanup handler" "${cleanup_handler}" "cleanup"
	add_cleanup_handler "${cleanup_handler}"

	return 0
}

function cleanup_tmpfs_for() {
	declare tmpfs_name="${1}"
	declare tmpfs_path="${2}"
	declare remove_dir="${3}"
	declare umount_tmpfs="${4}"

	# validate parameters
	if [[ -z "${tmpfs_name}" ]]; then
		exit_with_error "cleanup_tmpfs_for: tmpfs_name (arg 1) is empty"
	fi
	if [[ -z "${tmpfs_path}" ]]; then
		exit_with_error "cleanup_tmpfs_for: tmpfs_path (arg 2) is empty"
	fi
	if [[ -z "${remove_dir}" ]]; then
		exit_with_error "cleanup_tmpfs_for: remove_dir (arg 3) is empty"
	fi
	if [[ -z "${umount_tmpfs}" ]]; then
		exit_with_error "cleanup_tmpfs_for: umount_tmpfs (arg 4) is empty"
	fi

	# umount tmpfs
	if [[ "${umount_tmpfs}" == "umount_tmpfs" ]]; then
		display_alert "cleanup_tmpfs_for: umount tmpfs" "${tmpfs_name}" "cleanup"
		cd "${SRC}" || echo "cleanup_tmpfs_for: cd failed to ${SRC}" >&2 # avoid cwd in use error
		sync                                                             # let disk coalesce
		umount "${tmpfs_path}" &> /dev/null || {
			display_alert "cleanup_tmpfs_for: umount failed" "${tmpfs_name} tmpfs umount failed, will try lazy" "cleanup"
			# Do a lazy umount... last-resort...
			sync
			umount -l "${tmpfs_path}" &> /dev/null || display_alert "cleanup_tmpfs_for: lazy umount failed" "${tmpfs_name} tmpfs lazy umount also failed" "cleanup"
			sync
		}

		# Check if the tmpfs is still mounted after all that trying, log error, show debug, and give up with error
		mountpoint -q "${tmpfs_path}" && {
			display_alert "cleanup_tmpfs_for: umount failed" "${tmpfs_name} tmpfs still mounted after retries/lazy umount" "err"
			# Show last-resort what's in there / what's using it to stderr
			ls -la "${tmpfs_path}" >&2 || echo "cleanup_tmpfs_for: ls failed" >&2
			lsof "${tmpfs_path}" >&2 || echo "cleanup_tmpfs_for: lsof dir failed" >&2
			return 1 # sorry, we tried.
		} || {
			display_alert "cleanup_tmpfs_for: umount success" "${tmpfs_name}" "cleanup"
		}
	else
		display_alert "cleanup_tmpfs_for: not umounting tmpfs" "${tmpfs_name}" "cleanup"
	fi

	# remove the dir if we created it
	if [[ "${remove_dir}" == "remove_dir" ]]; then
		display_alert "cleanup_tmpfs_for: removing dir" "${tmpfs_path}" "cleanup"
		rm -rf "${tmpfs_path:?}"
	else
		display_alert "cleanup_tmpfs_for: not removing dir" "${tmpfs_path}" "cleanup"
	fi

	return 0
}

# Debugging utility.
function debug_tmpfs_show_usage() {
	if [[ "${SHOW_TMPFS}" == "yes" ]]; then
		display_alert "TMPFS debugging:" "${CURRENT_LOGGING_SECTION:-none} $*" "debug"
		run_host_command_logged df -h -t tmpfs "||" true
		run_host_command_logged free -m "||" true
	fi
	return 0
}
