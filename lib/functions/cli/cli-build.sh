function cli_standard_build_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_standard_build_run() {
	# configuration etc - it initializes the extension manager; handles its own logging sections
	prep_conf_main_build_single

	# the full build. It has its own logging sections.
	do_with_default_build full_build_packages_rootfs_and_image

	# CLI-specific: how to redo the build.
	if armbian_is_running_in_container; then
		BUILD_CONFIG='docker' # @TODO: this is not true, CLI handles this differently, gotta ask the CLI; this whole thing is inconsistent
	fi

	# Make it easy to repeat build by displaying build options used. Prepare array. @TODO this is inconsistent. Maybe something like the relaunch vars?
	local -a repeat_args=("./compile.sh" "${BUILD_CONFIG}" " BRANCH=${BRANCH}")
	[[ -n ${RELEASE} ]] && repeat_args+=("RELEASE=${RELEASE}")
	[[ -n ${BUILD_MINIMAL} ]] && repeat_args+=("BUILD_MINIMAL=${BUILD_MINIMAL}")
	[[ -n ${BUILD_DESKTOP} ]] && repeat_args+=("BUILD_DESKTOP=${BUILD_DESKTOP}")
	[[ -n ${KERNEL_ONLY} ]] && repeat_args+=("KERNEL_ONLY=${KERNEL_ONLY}")
	[[ -n ${KERNEL_CONFIGURE} ]] && repeat_args+=("KERNEL_CONFIGURE=${KERNEL_CONFIGURE}")
	[[ -n ${DESKTOP_ENVIRONMENT} ]] && repeat_args+=("DESKTOP_ENVIRONMENT=${DESKTOP_ENVIRONMENT}")
	[[ -n ${DESKTOP_ENVIRONMENT_CONFIG_NAME} ]] && repeat_args+=("DESKTOP_ENVIRONMENT_CONFIG_NAME=${DESKTOP_ENVIRONMENT_CONFIG_NAME}")
	[[ -n ${DESKTOP_APPGROUPS_SELECTED} ]] && repeat_args+=("DESKTOP_APPGROUPS_SELECTED=\"${DESKTOP_APPGROUPS_SELECTED}\"")
	[[ -n ${DESKTOP_APT_FLAGS_SELECTED} ]] && repeat_args+=("DESKTOP_APT_FLAGS_SELECTED=\"${DESKTOP_APT_FLAGS_SELECTED}\"")
	[[ -n ${COMPRESS_OUTPUTIMAGE} ]] && repeat_args+=("COMPRESS_OUTPUTIMAGE=${COMPRESS_OUTPUTIMAGE}")
	display_alert "Repeat Build Options" "${repeat_args[*]}" "ext" # * = expand array, space delimited, single-word.
}
