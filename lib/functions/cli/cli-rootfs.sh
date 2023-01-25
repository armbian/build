function cli_rootfs_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_rootfs_run() {
	declare -g ROOTFS_COMPRESSION_RATIO="${ROOTFS_COMPRESSION_RATIO:-"15"}" # default to Compress stronger when we make rootfs cache

	declare -a vars_cant_be_set=("LINUXFAMILY" "BOARDFAMILY")
	# loop through all vars and check if they are set and bomb out
	for var in "${vars_cant_be_set[@]}"; do
		if [[ -n ${!var} ]]; then
			exit_with_error "Param '${var}' is set ('${!var}') but can't be set for rootfs CLI; rootfs's are shared across boards and families."
		fi
	done

	# If BOARD is set, use it to convert to an ARCH.
	if [[ -n ${BOARD} ]]; then
		display_alert "BOARD is set, converting to ARCH for rootfs building" "'BOARD=${BOARD}'" "warn"
		# Convert BOARD to ARCH; source the BOARD and FAMILY stuff
		LOG_SECTION="config_source_board_file" do_with_conditional_logging config_source_board_file
		LOG_SECTION="source_family_config_and_arch" do_with_conditional_logging source_family_config_and_arch
		display_alert "Done sourcing board file" "'${BOARD}' - arch: '${ARCH}'" "warn"
	fi

	declare -a vars_need_to_be_set=("RELEASE" "ARCH")
	# loop through all vars and check if they are not set and bomb out if so
	for var in "${vars_need_to_be_set[@]}"; do
		if [[ -z ${!var} ]]; then
			exit_with_error "Param '${var}' is not set but needs to be set for rootfs CLI."
		fi
	done

	declare -r __wanted_rootfs_arch="${ARCH}"
	declare -g -r RELEASE="${RELEASE}" # make readonly for finding who tries to change it
	declare -g -r NEEDS_BINFMT="yes"   # make sure binfmts are installed during prepare_host_interactive

	# configuration etc - it initializes the extension manager; handles its own logging sections.
	prep_conf_main_only_rootfs < /dev/null # no stdin for this, so it bombs if tries to be interactive.

	declare -g -r ARCH="${ARCH}" # make readonly for finding who tries to change it
	if [[ "${ARCH}" != "${__wanted_rootfs_arch}" ]]; then
		exit_with_error "Param 'ARCH' is set to '${ARCH}' after config, but different from wanted '${__wanted_rootfs_arch}'"
	fi

	declare -g ROOT_FS_CREATE_VERSION
	if [[ -z ${ROOT_FS_CREATE_VERSION} ]]; then
		ROOT_FS_CREATE_VERSION="$(date --utc +"%Y%m%d")"
		display_alert "ROOT_FS_CREATE_VERSION is not set, defaulting to current date" "ROOT_FS_CREATE_VERSION=${ROOT_FS_CREATE_VERSION}" "info"
	else
		display_alert "ROOT_FS_CREATE_VERSION is set" "ROOT_FS_CREATE_VERSION=${ROOT_FS_CREATE_VERSION}" "info"
	fi

	# default build, but only invoke specific rootfs functions needed. It has its own logging sections.
	do_with_default_build cli_rootfs_only_in_default_build < /dev/null # no stdin for this, so it bombs if tries to be interactive.

	reset_uid_owner "${BUILT_ROOTFS_CACHE_FILE}"

	display_alert "Rootfs build complete" "${BUILT_ROOTFS_CACHE_NAME}" "info"
	display_alert "Rootfs build complete, file: " "${BUILT_ROOTFS_CACHE_FILE}" "info"
}

# This is run inside do_with_default_build(), above.
function cli_rootfs_only_in_default_build() {
	declare -g rootfs_cache_id="none_yet"

	LOG_SECTION="prepare_rootfs_build_params_and_trap" do_with_logging prepare_rootfs_build_params_and_trap

	LOG_SECTION="calculate_rootfs_cache_id" do_with_logging calculate_rootfs_cache_id # sets rootfs_cache_id

	# Set a GHA output variable for the cache ID, so it can be used in other steps.
	github_actions_add_output rootfs_cache_id_version "${rootfs_cache_id}-${ROOT_FS_CREATE_VERSION}" # for real filename
	github_actions_add_output rootfs_cache_id "${rootfs_cache_id}"                                   # for actual caching, sans date/version
	# In GHA, prefer to reference this output variable, as it is more stable; I wanna move it to output/rootfs dir later.
	github_actions_add_output rootfs_out_filename_relative "cache/rootfs/${ARCH}-${RELEASE}-${rootfs_cache_id}-${ROOT_FS_CREATE_VERSION}.tar.zst"

	display_alert "Going to build rootfs" "packages_hash: '${packages_hash:-}' cache_type: '${cache_type:-}' rootfs_cache_id: '${rootfs_cache_id}'" "info"

	# "rootfs" CLI skips over a lot goes straight to create the rootfs. It doesn't check cache etc.
	LOG_SECTION="create_new_rootfs_cache" do_with_logging create_new_rootfs_cache
}
