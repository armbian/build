function cli_undecided_pre_run() {
	# If undecided, run the 'build' command.
	# 'build' will then defer to 'docker' if ran on Darwin.
	# so save a trip, check if we're on Darwin right here.
	if [[ "$(uname)" == "Linux" ]]; then
		display_alert "Linux!" "func cli_undecided_pre_run go to build" "debug"
		ARMBIAN_CHANGE_COMMAND_TO="build"
	else
		display_alert "Not under Linux; use docker..." "func cli_undecided_pre_run go to docker" "debug"
		ARMBIAN_CHANGE_COMMAND_TO="docker"
	fi
}

function cli_undecided_run() {
	exit_with_error "Should never run the undecided command. How did this happen?"
}
