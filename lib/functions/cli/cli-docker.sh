function cli_docker_pre_run() {
	if [[ "${DOCKERFILE_GENERATE_ONLY}" == "yes" ]]; then
		display_alert "Dockerfile generation only" "func cli_docker_pre_run" "debug"
		return 0
	fi

	# make sure we're not _ALREADY_ running under docker... otherwise eternal loop?
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then
		exit_with_error "asking for docker... inside docker. how did this happen? so sorry."
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
	produce_relaunch_parameters # produces ARMBIAN_CLI_RELAUNCH_ARGS

	case "${DOCKER_SUBCMD}" in
		shell)
			display_alert "Launching Docker shell" "docker-shell" "info"
			docker run -it "${DOCKER_ARGS[@]}" "${DOCKER_ARMBIAN_INITIAL_IMAGE_TAG}" /bin/bash
			;;

		purge)
			display_alert "Purging unused Docker volumes" "docker-purge" "info"
			docker_purge_deprecated_volumes
			;;

		*)
			docker_cli_launch "${ARMBIAN_CLI_RELAUNCH_ARGS[@]}" # MARK: this "re-launches" using the passed params.
			;;
	esac

}
