function cli_docker_pre_run() {
	if [[ "${DOCKERFILE_GENERATE_ONLY}" == "yes" ]]; then
		display_alert "Dockerfile generation only" "func cli_docker_pre_run" "debug"
		return 0
	fi

	case "${DOCKER_SUBCMD}" in
		shell)
			# inside-function-function: a dynamic hook, only triggered if this CLI runs.
			function add_host_dependencies__ssh_client_for_docker_shell_over_ssh() {
				export EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} openssh-client"
			}
			declare -g DOCKER_PASS_SSH_AGENT="yes" # Pass SSH agent to docker
			;;
	esac

	# make sure we're not _ALREADY_ running under docker... otherwise eternal loop?
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then
		exit_with_error "asking for docker... inside docker. how did this happen? Tip: you don't need 'docker' to run armbian-next inside Docker; it's automatically detected and used when appropriate."
	fi
}

function cli_docker_run() {
	# Docker won't have ${SRC}/.git, so precalculate the git-info header so it can be included in the inside-Docker logs.
	# It's gonna be picked up by export_ansi_logs() and included in the final log, if it exists.
	declare -g GIT_INFO_ANSI
	GIT_INFO_ANSI="$(prepare_ansi_git_info_log_header)"

	LOG_SECTION="docker_cli_prepare" do_with_logging docker_cli_prepare

	# @TODO: and can be very well said that in CI, we always want FAST_DOCKER=yes, unless we're building the Docker image itself.
	if [[ "${FAST_DOCKER:-"no"}" != "yes" ]]; then # "no, I want *slow* docker" -- no one, ever
		LOG_SECTION="docker_cli_prepare_dockerfile" do_with_logging docker_cli_prepare_dockerfile

		if [[ "${DOCKERFILE_GENERATE_ONLY}" == "yes" ]]; then
			display_alert "Dockerfile generated" "exiting" "info"
			exit 0
		fi

		LOG_SECTION="docker_cli_build_dockerfile" do_with_logging docker_cli_build_dockerfile
	fi

	LOG_SECTION="docker_cli_prepare_launch" do_with_logging docker_cli_prepare_launch

	ARMBIAN_CLI_RELAUNCH_PARAMS+=(["SET_OWNER_TO_UID"]="${EUID}")                 # fix the owner of files to our UID
	ARMBIAN_CLI_RELAUNCH_PARAMS+=(["ARMBIAN_BUILD_UUID"]="${ARMBIAN_BUILD_UUID}") # pass down our uuid to the docker instance
	ARMBIAN_CLI_RELAUNCH_PARAMS+=(["SKIP_LOG_ARCHIVE"]="yes")                     # launched docker instance will not cleanup logs.

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
			# this does NOT exit with the same exit code as the docker instance.
			# instead, it sets the docker_exit_code variable.
			declare -i docker_exit_code docker_produced_logs=0
			docker_cli_launch "${ARMBIAN_CLI_RELAUNCH_ARGS[@]}" # MARK: this "re-launches" using the passed params.

			# Set globals to avoid:
			# 1) showing the controlling host's log; we only want to show a ref to the Docker logfile, unless it didn't produce one.
			#    If it did produce one, it's "link" is already shown above.
			if [[ $docker_produced_logs -gt 0 ]]; then
				declare -g show_message_after_export="skip" # handled by export_ansi_logs()
			fi
			# 2) actually exiting with the same error code as the docker instance, but without triggering an error.
			declare -g -i global_final_exit_code=$docker_exit_code # handled by .... @TODO
			;;

	esac

}
