desktop_element_available_for_arch() {
	local desktop_element_path="${1}"
	local targeted_arch="${2}"

	local arch_limitation_file="${1}/only_for"

	echo "Checking if ${desktop_element_path} is available for ${targeted_arch} in ${arch_limitation_file}" >> "${DEST}"/${LOG_SUBPATH}/output.log
	if [[ -f "${arch_limitation_file}" ]]; then
		grep -- "${targeted_arch}" "${arch_limitation_file}"
		return $?
	else
		return 0
	fi
}

desktop_element_supported() {

	local desktop_element_path="${1}"

	local support_level_filepath="${desktop_element_path}/support"
	if [[ -f "${support_level_filepath}" ]]; then
		local support_level="$(cat "${support_level_filepath}")"
		if [[ "${support_level}" != "supported" && "${EXPERT}" != "yes" ]]; then
			return 65
		fi

		desktop_element_available_for_arch "${desktop_element_path}" "${ARCH}"
		if [[ $? -ne 0 ]]; then
			return 66
		fi
	else
		return 64
	fi

	return 0

}

desktop_environments_prepare_menu() {
	for desktop_env_dir in "${DESKTOP_CONFIGS_DIR}/"*; do
		local desktop_env_name=$(basename ${desktop_env_dir})
		local expert_infos=""
		[[ "${EXPERT}" == "yes" ]] && expert_infos="[$(cat "${desktop_env_dir}/support" 2> /dev/null)]"
		desktop_element_supported "${desktop_env_dir}" "${ARCH}" && options+=("${desktop_env_name}" "${desktop_env_name^} desktop environment ${expert_infos}")
	done
}

desktop_environment_check_if_valid() {

	local error_msg=""
	desktop_element_supported "${DESKTOP_ENVIRONMENT_DIRPATH}" "${ARCH}"
	local retval=$?

	if [[ ${retval} == 0 ]]; then
		return
	elif [[ ${retval} == 64 ]]; then
		error_msg+="Either the desktop environment ${DESKTOP_ENVIRONMENT} does not exist "
		error_msg+="or the file ${DESKTOP_ENVIRONMENT_DIRPATH}/support is missing"
	elif [[ ${retval} == 65 ]]; then
		error_msg+="Only experts can build an image with the desktop environment \"${DESKTOP_ENVIRONMENT}\", since the Armbian team won't offer any support for it (EXPERT=${EXPERT})"
	elif [[ ${retval} == 66 ]]; then
		error_msg+="The desktop environment \"${DESKTOP_ENVIRONMENT}\" has no packages for your targeted board architecture (BOARD=${BOARD} ARCH=${ARCH}). "
		error_msg+="The supported boards architectures are : "
		error_msg+="$(cat "${DESKTOP_ENVIRONMENT_DIRPATH}/only_for")"
	fi

	# supress error when cache is rebuilding
	[[ -n "$ROOT_FS_CREATE_ONLY" ]] && exit 0

	exit_with_error "${error_msg}"
}
