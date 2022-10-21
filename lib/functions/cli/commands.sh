function armbian_register_commands() {
	# More than one command can map to the same handler. In that case, use ARMBIAN_COMMANDS_TO_VARS_DICT for specific vars.
	declare -g -A ARMBIAN_COMMANDS_TO_HANDLERS_DICT=(
		["docker"]="docker"              # thus requires cli_docker_pre_run and cli_docker_run
		["docker-purge"]="docker"        # idem
		["dockerpurge"]="docker"         # idem
		["docker-shell"]="docker"        # idem
		["dockershell"]="docker"         # idem
		["generate-dockerfile"]="docker" # idem

		["vagrant"]="vagrant" # thus requires cli_vagrant_pre_run and cli_vagrant_run

		["requirements"]="requirements" # implemented in cli_requirements_pre_run and cli_requirements_run # @TODO

		["config-dump"]="config_dump" # implemented in cli_config_dump_pre_run and cli_config_dump_run # @TODO
		["configdump"]="config_dump"  # idem

		["build"]="standard_build" # implemented in cli_standard_build_pre_run and cli_standard_build_run

		["undecided"]="undecided" # implemented in cli_undecided_pre_run and cli_undecided_run - relaunches either build or docker
	)

	# Vars to be set for each command. Optional.
	declare -g -A ARMBIAN_COMMANDS_TO_VARS_DICT=(
		["docker-purge"]="DOCKER_SUBCMD='purge'"
		["dockerpurge"]="DOCKER_SUBCMD='purge'"

		["docker-shell"]="DOCKER_SUBCMD='shell'"
		["dockershell"]="DOCKER_SUBCMD='shell'"

		["generate-dockerfile"]="DOCKERFILE_GENERATE_ONLY='yes'"

		["requirements"]="REQUIREMENTS_DEFS_ONLY='yes'"

		["config-dump"]="CONFIG_DEFS_ONLY='yes'"
		["configdump"]="CONFIG_DEFS_ONLY='yes'"

	)

	# Override the LOG_CLI_ID to change the log file name.
	# Will be set to ARMBIAN_COMMAND if not set after all pre-runs done.
	declare -g ARMBIAN_LOG_CLI_ID

	# Keep a running dict of params/variables. Can't repeat stuff here. Dict.
	declare -g -A ARMBIAN_CLI_RELAUNCH_PARAMS=(["ARMBIAN_RELAUNCHED"]="yes")

	# Keep a running array of config files needed for relaunch.
	declare -g -a ARMBIAN_CLI_RELAUNCH_CONFIGS=()
}
