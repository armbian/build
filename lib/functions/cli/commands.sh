function armbian_register_commands() {
	# More than one command can map to the same handler. In that case, use ARMBIAN_COMMANDS_TO_VARS_DICT for specific vars.
	declare -g -A ARMBIAN_COMMANDS_TO_HANDLERS_DICT=(
		["docker"]="docker"              # thus requires cli_docker_pre_run and cli_docker_run
		["docker-purge"]="docker"        # idem @TODO unimplemented!!!
		["dockerpurge"]="docker"         # idem @TODO unimplemented!!!
		["docker-shell"]="docker"        # idem @TODO unimplemented!!!
		["dockershell"]="docker"         # idem @TODO unimplemented!!!
		["generate-dockerfile"]="docker" # idem

		["vagrant"]="vagrant" # thus requires cli_vagrant_pre_run and cli_vagrant_run

		["requirements"]="requirements" # implemented in cli_requirements_pre_run and cli_requirements_run

		["config-dump"]="config_dump" # implemented in cli_config_dump_pre_run and cli_config_dump_run
		["configdump"]="config_dump"  # idem

		["json-info"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run

		["build"]="standard_build" # implemented in cli_standard_build_pre_run and cli_standard_build_run
		["distccd"]="distccd"      # implemented in cli_distccd_pre_run and cli_distccd_run

		["undecided"]="undecided" # implemented in cli_undecided_pre_run and cli_undecided_run - relaunches either build or docker
	)

	# Vars to be set for each command. Optional.
	declare -g -A ARMBIAN_COMMANDS_TO_VARS_DICT=(
		["docker-purge"]="DOCKER_SUBCMD='purge'" # @TODO unimplemented!
		["dockerpurge"]="DOCKER_SUBCMD='purge'"  # @TODO unimplemented!
		["docker-shell"]="DOCKER_SUBCMD='shell'" # @TODO unimplemented!
		["dockershell"]="DOCKER_SUBCMD='shell'"  # @TODO unimplemented!

		["generate-dockerfile"]="DOCKERFILE_GENERATE_ONLY='yes'"

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
