function cli_requirements_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	if [[ "$(uname)" != "Linux" ]]; then
		display_alert "Not running on Linux" "refusing to run 'requirements'" "err"
		exit 1
	fi

	if [[ "${EUID}" == "0" ]]; then # we're already root. Either running as real root, or already sudo'ed.
		display_alert "Already running as root" "great" "debug"
	else
		# Fail, installing requirements is not allowed as non-root.
		exit_with_error "This command requires root privileges - refusing to run"
	fi
}

function cli_requirements_run() {
	initialize_extension_manager # initialize the extension manager.
	declare -a -g host_dependencies=()
	early_prepare_host_dependencies
	LOG_SECTION="install_host_dependencies" do_with_logging install_host_dependencies "for requirements command"
	display_alert "Done with" "@host dependencies" "cachehit"
}
