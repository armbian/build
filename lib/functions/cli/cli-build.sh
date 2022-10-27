function cli_standard_build_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine" 
	cli_standard_relaunch_docker_or_sudo
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
