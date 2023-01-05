function cli_standard_build_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_standard_build_run() {
	# configuration etc - it initializes the extension manager; handles its own logging sections
	prepare_and_config_main_build_single

	# main_default_build_single() handles its own logging sections...
	main_default_build_single
}
