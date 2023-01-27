function cli_standard_build_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_standard_build_run() {
	# configuration etc - it initializes the extension manager; handles its own logging sections
	prep_conf_main_build_single

	# 1x: show interactively-selected as soon as possible, after config
	produce_repeat_args_array
	display_alert "Repeat Build Options (early)" "${repeat_args[*]}" "ext"

	# the full build. It has its own logging sections.
	do_with_default_build full_build_packages_rootfs_and_image

	# 1x: show interactively-selected as soon as possible, after config
	produce_repeat_args_array
	display_alert "Repeat Build Options" "${repeat_args[*]}" "ext" # * = expand array, space delimited, single-word.

}

function produce_repeat_args_array() {
	# Make it easy to repeat build by displaying build options used. Prepare array.
	declare -a -g repeat_args=("./compile.sh")
	# @TODO: missing the config file name, if any.
	# @TODO: missing the original cli command, if different from build/docker
	[[ -n ${BOARD} ]] && repeat_args+=("BOARD=${BOARD}")
	[[ -n ${BRANCH} ]] && repeat_args+=("BRANCH=${BRANCH}")
	[[ -n ${RELEASE} ]] && repeat_args+=("RELEASE=${RELEASE}")
	[[ -n ${BUILD_MINIMAL} ]] && repeat_args+=("BUILD_MINIMAL=${BUILD_MINIMAL}")
	[[ -n ${BUILD_DESKTOP} ]] && repeat_args+=("BUILD_DESKTOP=${BUILD_DESKTOP}")
	[[ -n ${KERNEL_ONLY} ]] && repeat_args+=("KERNEL_ONLY=${KERNEL_ONLY}")
	[[ -n ${KERNEL_CONFIGURE} ]] && repeat_args+=("KERNEL_CONFIGURE=${KERNEL_CONFIGURE}")
	[[ -n ${DESKTOP_ENVIRONMENT} ]] && repeat_args+=("DESKTOP_ENVIRONMENT=${DESKTOP_ENVIRONMENT}")
	[[ -n ${DESKTOP_ENVIRONMENT_CONFIG_NAME} ]] && repeat_args+=("DESKTOP_ENVIRONMENT_CONFIG_NAME=${DESKTOP_ENVIRONMENT_CONFIG_NAME}")
	[[ -n ${DESKTOP_APPGROUPS_SELECTED} ]] && repeat_args+=("DESKTOP_APPGROUPS_SELECTED=\"${DESKTOP_APPGROUPS_SELECTED:-"none"}\"")
	[[ -n ${COMPRESS_OUTPUTIMAGE} ]] && repeat_args+=("COMPRESS_OUTPUTIMAGE=${COMPRESS_OUTPUTIMAGE}")
}
