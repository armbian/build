function desktop_element_available_for_arch() {
	local desktop_element_path="${1}"
	local targeted_arch="${2}"
	local arch_limitation_file="${1}/only_for"
	echo "Checking if ${desktop_element_path} is available for ${targeted_arch} in ${arch_limitation_file}" >> "${DEST}"/${LOG_SUBPATH}/output.log
	if [[ -f "${arch_limitation_file}" ]]; then
		if ! grep -- "${targeted_arch}" "${arch_limitation_file}"; then
			return 1
		fi
	fi
	return 0
}

function desktop_element_supported() {
	local desktop_element_path="${1}"
	local support_level_filepath="${desktop_element_path}/support"
	export desktop_element_supported_result=0
	if [[ -f "${support_level_filepath}" ]]; then
		local support_level="$(cat "${support_level_filepath}")"
		if [[ "${support_level}" != "supported" && "${EXPERT}" != "yes" ]]; then
			desktop_element_supported_result=65
			return 0
		fi
		if ! desktop_element_available_for_arch "${desktop_element_path}" "${ARCH}"; then
			desktop_element_supported_result=66
			return 0
		fi
	else
		desktop_element_supported_result=64
		return 0
	fi
	return 0
}

function desktop_environments_prepare_menu() {
	for desktop_env_dir in "${DESKTOP_CONFIGS_DIR}/"*; do
		local desktop_env_name expert_infos="" desktop_element_supported_result=0
		desktop_env_name=$(basename ${desktop_env_dir})
		[[ "${EXPERT}" == "yes" ]] && expert_infos="[$(cat "${desktop_env_dir}/support" 2> /dev/null)]"
		desktop_element_supported "${desktop_env_dir}" "${ARCH}"
		[[ ${desktop_element_supported_result} == 0 ]] && options+=("${desktop_env_name}" "${desktop_env_name^} desktop environment ${expert_infos}")
	done
	return 0
}

function desktop_environment_check_if_valid() {
	local error_msg="" desktop_element_supported_result=0
	desktop_element_supported "${DESKTOP_ENVIRONMENT_DIRPATH}" "${ARCH}"

	if [[ ${desktop_element_supported_result} == 0 ]]; then
		return
	elif [[ ${desktop_element_supported_result} == 64 ]]; then
		error_msg+="Either the desktop environment ${DESKTOP_ENVIRONMENT} does not exist "
		error_msg+="or the file ${DESKTOP_ENVIRONMENT_DIRPATH}/support is missing"
	elif [[ ${desktop_element_supported_result} == 65 ]]; then
		error_msg+="Only experts can build an image with the desktop environment \"${DESKTOP_ENVIRONMENT}\", since the Armbian team won't offer any support for it (EXPERT=${EXPERT})"
	elif [[ ${desktop_element_supported_result} == 66 ]]; then
		error_msg+="The desktop environment \"${DESKTOP_ENVIRONMENT}\" has no packages for your targeted board architecture (BOARD=${BOARD} ARCH=${ARCH}). "
		error_msg+="The supported boards architectures are : "
		error_msg+="$(cat "${DESKTOP_ENVIRONMENT_DIRPATH}/only_for")"
	fi

	# supress error when cache is rebuilding
	[[ -n "$ROOT_FS_CREATE_ONLY" ]] && exit 0

	exit_with_error "${error_msg}"
}

function desktop_main_configuration_interactive() {

	# Myy : Once we got a list of selected groups, parse the PACKAGE_LIST inside configuration.sh
	DESKTOP_ELEMENTS_DIR="${SRC}/config/desktop/${RELEASE}"
	DESKTOP_CONFIGS_DIR="${DESKTOP_ELEMENTS_DIR}/environments"
	DESKTOP_CONFIG_PREFIX="config_"
	DESKTOP_APPGROUPS_DIR="${DESKTOP_ELEMENTS_DIR}/appgroups"

	display_alert "Handling some" "desktop config stuff 1" "${DESKTOP_CONFIGS_DIR}" "debug"

	if [[ $BUILD_DESKTOP == "yes" && -z $DESKTOP_ENVIRONMENT ]]; then
		options=()
		desktop_environments_prepare_menu
		if [[ "${options[0]}" == "" ]]; then
			exit_with_error "No desktop environment seems to be available for your board ${BOARD} (ARCH : ${ARCH} - EXPERT : ${EXPERT})"
		fi
		DESKTOP_ENVIRONMENT=$(show_menu "Choose a desktop environment" "$backtitle" "Select the default desktop environment to bundle with this image" "${options[@]}")
		unset options
		if [[ -z "${DESKTOP_ENVIRONMENT}" ]]; then
			exit_with_error "No desktop environment selected..."
		fi
	fi
	display_alert "Handling some" "desktop config stuff 2" "debug"

	if [[ $BUILD_DESKTOP == "yes" ]]; then
		DESKTOP_ENVIRONMENT_DIRPATH="${DESKTOP_CONFIGS_DIR}/${DESKTOP_ENVIRONMENT}"
		desktop_environment_check_if_valid # Make sure desktop config is sane.
	fi

	display_alert "Handling some" "desktop config stuff 3" "debug"

	if [[ $BUILD_DESKTOP == "yes" && -z $DESKTOP_ENVIRONMENT_CONFIG_NAME ]]; then
		# FIXME Check for empty folders, just in case the current maintainer
		# messed up
		# Note, we could also ignore it and don't show anything in the previous
		# menu, but that hides information and make debugging harder, which I
		# don't like. Adding desktop environments as a maintainer is not a
		# trivial nor common task.

		options=()
		for configuration in "${DESKTOP_ENVIRONMENT_DIRPATH}/${DESKTOP_CONFIG_PREFIX}"*; do
			config_filename=$(basename ${configuration})
			config_name=${config_filename#"${DESKTOP_CONFIG_PREFIX}"}
			options+=("${config_filename}" "${config_name} configuration")
		done

		DESKTOP_ENVIRONMENT_CONFIG_NAME=$(show_menu "Choose the desktop environment config" "$backtitle" "Select the configuration for this environment.\nThese are sourced from ${desktop_environment_config_dir}" "${options[@]}")
		unset options

		if [[ -z $DESKTOP_ENVIRONMENT_CONFIG_NAME ]]; then
			exit_with_error "No desktop configuration selected... Do you really want a desktop environment ?"
		fi
	fi
	display_alert "Handling some" "desktop config stuff 4" "debug"

	if [[ $BUILD_DESKTOP == "yes" ]]; then
		DESKTOP_ENVIRONMENT_PACKAGE_LIST_DIRPATH="${DESKTOP_ENVIRONMENT_DIRPATH}/${DESKTOP_ENVIRONMENT_CONFIG_NAME}"
		DESKTOP_ENVIRONMENT_PACKAGE_LIST_FILEPATH="${DESKTOP_ENVIRONMENT_PACKAGE_LIST_DIRPATH}/packages"
	fi

	# "-z ${VAR+x}" allows to check for unset variable
	# Technically, someone might want to build a desktop with no additional
	# appgroups.
	if [[ $BUILD_DESKTOP == "yes" && -z ${DESKTOP_APPGROUPS_SELECTED+x} ]]; then
		options=()
		for appgroup_path in "${DESKTOP_APPGROUPS_DIR}/"*; do
			appgroup="$(basename "${appgroup_path}")"
			options+=("${appgroup}" "${appgroup^}" off)
		done
		# FIXME: pardini: here's a subshell to run dialog. in the middle of the main config. refactor this away
		DESKTOP_APPGROUPS_SELECTED=$(
			show_select_menu \
				"Choose desktop softwares to add" \
				"$backtitle" \
				"Select which kind of softwares you'd like to add to your build" \
				"${options[@]}"
		)
		unset options
	fi
	display_alert "Done with" "desktop config stuff - END" "debug"
}
