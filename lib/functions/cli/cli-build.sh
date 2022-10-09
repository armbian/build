function cli_standard_build_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# Super early handling. If no command and not root, become root by using sudo. Some exceptions apply.
	if [[ "${EUID}" == "0" ]]; then # we're already root. Either running as real root, or already sudo'ed.
		display_alert "Already running as root" "great" "debug"
	else # not root.
		# Pass the current UID to any further relaunchings (under docker or sudo).
		ARMBIAN_CLI_RELAUNCH_PARAMS+=(["SET_OWNER_TO_UID"]="${EUID}") # add params when relaunched under docker

		# We've a few options.
		# 1) We could check if Docker is working, and do everything under Docker. Users who can use Docker, can "become" root inside a container.
		# 2) We could ask for sudo (which _might_ require a password)...
		# @TODO: GitHub actions can do both. Sudo without password _and_ Docker; should we prefer Docker? Might have unintended consequences...
		if is_docker_ready_to_go; then
			# add the current user EUID as a parameter when it's relaunched under docker. SET_OWNER_TO_UID="${EUID}"
			display_alert "Trying to build, not root, but Docker is ready to go" "delegating to Docker" "debug"
			ARMBIAN_CHANGE_COMMAND_TO="docker"
			return 0
		fi

		# check if we're on Linux via uname. if not, refuse to do anything.
		if [[ "$(uname)" != "Linux" ]]; then
			display_alert "Not running on Linux; Docker is not available" "refusing to run" "err"
			exit 1
		fi

		display_alert "This script requires root privileges; Docker is unavailable" "trying to use sudo" "wrn"
		declare -g ARMBIAN_CLI_RELAUNCH_ARGS=()
		produce_relaunch_parameters                                               # produces ARMBIAN_CLI_RELAUNCH_ARGS
		sudo --preserve-env "${SRC}/compile.sh" "${ARMBIAN_CLI_RELAUNCH_ARGS[@]}" # MARK: relaunch done here!
		display_alert "AFTER SUDO!!!" "AFTER SUDO!!!" "warn"
	fi
}

function cli_standard_build_run() {
	# @TODO: then many other interesting possibilities like a REPL, which we lost somewhere along the way. docker-shell?

	# configuration etc - it initializes the extension manager
	prepare_and_config_main_build_single

	# Allow for custom user-invoked functions, or do the default build.
	if [[ -z $1 ]]; then
		main_default_build_single
	else
		# @TODO: rpardini: check this with extensions usage?
		eval "$@"
	fi
}
