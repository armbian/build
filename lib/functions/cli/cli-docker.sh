function cli_docker_pre_run() {
	if [[ "${DOCKERFILE_GENERATE_ONLY}" == "yes" ]]; then
		display_alert "Dockerfile generation only" "func cli_docker_pre_run" "debug"
		return 0
	fi

	# make sure we're not _ALREADY_ running under docker... otherwise eternal loop?
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then
		display_alert "wtf" "asking for docker... inside docker; turning to build command" "warn"
		# @TODO: wrong, what if we wanna run other stuff inside Docker? not build?
		ARMBIAN_CHANGE_COMMAND_TO="build"
	fi

}

function cli_docker_run() {
	LOG_SECTION="docker_cli_prepare" do_with_logging docker_cli_prepare

	if [[ "${DOCKERFILE_GENERATE_ONLY}" == "yes" ]]; then
		display_alert "Dockerfile generated" "exiting" "info"
		exit 0
	fi

	LOG_SECTION="docker_cli_build_dockerfile" do_with_logging docker_cli_build_dockerfile

	LOG_SECTION="docker_cli_prepare_launch" do_with_logging docker_cli_prepare_launch

	ARMBIAN_CLI_RELAUNCH_PARAMS+=(["SET_OWNER_TO_UID"]="${EUID}")                 # fix the owner of files to our UID
	ARMBIAN_CLI_RELAUNCH_PARAMS+=(["ARMBIAN_BUILD_UUID"]="${ARMBIAN_BUILD_UUID}") # pass down our uuid to the docker instance
	ARMBIAN_CLI_RELAUNCH_PARAMS+=(["SKIP_LOG_ARCHIVE"]="yes")                     # launched docker instance will not cleanup logs.
	declare -g SKIP_LOG_ARCHIVE=yes                                               # Don't archive logs in the parent instance either.

	declare -g ARMBIAN_CLI_RELAUNCH_ARGS=()
	produce_relaunch_parameters                         # produces ARMBIAN_CLI_RELAUNCH_ARGS
	docker_cli_launch "${ARMBIAN_CLI_RELAUNCH_ARGS[@]}" # MARK: this "re-launches" using the passed params.
}
