function cli_undecided_pre_run() {
	# If undecided, run the 'build' command.
	display_alert "cli_undecided_pre_run" "func cli_undecided_pre_run go to build" "debug"
	ARMBIAN_CHANGE_COMMAND_TO="build"
}

function cli_undecided_run() {
	exit_with_error "Should never run the undecided command. How did this happen?"
}
