function armbian_register_commands() {
	# More than one command can map to the same handler. In that case, use ARMBIAN_COMMANDS_TO_VARS_DICT for specific vars.
	declare -g -A ARMBIAN_COMMANDS_TO_HANDLERS_DICT=(
		["docker"]="docker" # thus requires cli_docker_pre_run and cli_docker_run
		["docker-purge"]="docker"
		["dockerpurge"]="docker"
		["docker-shell"]="docker"
		["dockershell"]="docker"
		["generate-dockerfile"]="docker"

		["vagrant"]="vagrant" # thus requires cli_vagrant_pre_run and cli_vagrant_run

		["requirements"]="requirements" # implemented in cli_requirements_pre_run and cli_requirements_run

		["config-dump"]="config_dump" # implemented in cli_config_dump_pre_run and cli_config_dump_run
		["configdump"]="config_dump"  # idem

		["json-info"]="json_info" # implemented in cli_json_info_pre_run and cli_json_info_run

		["kernel-patches-to-git"]="patch_kernel" # implemented in cli_patch_kernel_pre_run and cli_patch_kernel_run

		["build"]="standard_build" # implemented in cli_standard_build_pre_run and cli_standard_build_run
		["distccd"]="distccd"      # implemented in cli_distccd_pre_run and cli_distccd_run

		["rootfs"]="rootfs"       # implemented in cli_rootfs_pre_run and cli_rootfs_run

		# shortcuts, see vars set below. the use legacy single build, and try to control it via variables
		["kernel"]="standard_build"
		["u-boot"]="standard_build"
		["uboot"]="standard_build"

		# external tooling, made easy.
		["oras-upload"]="oras" # implemented in cli_oras_pre_run and cli_oras_run; up/down/info are the same, see vars below

		["undecided"]="undecided" # implemented in cli_undecided_pre_run and cli_undecided_run - relaunches either build or docker
	)

	# Vars to be set for each command. Optional.
	declare -g -A ARMBIAN_COMMANDS_TO_VARS_DICT=(
		["docker-purge"]="DOCKER_SUBCMD='purge'"
		["dockerpurge"]="DOCKER_SUBCMD='purge'"
		["docker-shell"]="DOCKER_SUBCMD='shell'"
		["dockershell"]="DOCKER_SUBCMD='shell'"

		["generate-dockerfile"]="DOCKERFILE_GENERATE_ONLY='yes'"

		["config-dump"]="CONFIG_DEFS_ONLY='yes'"
		["configdump"]="CONFIG_DEFS_ONLY='yes'"

		["kernel"]="KERNEL_ONLY='yes' JUST_KERNEL='yes' KERNEL_IGNORE_DEB='yes'"
		["u-boot"]="KERNEL_ONLY='yes' JUST_UBOOT='yes' UBOOT_IGNORE_DEB='yes'"
		["uboot"]="KERNEL_ONLY='yes' JUST_UBOOT='yes' UBOOT_IGNORE_DEB='yes'"

		["oras-upload"]="ORAS_OPERATION='upload'"

		["undecided"]="UNDECIDED='yes'"
	)
	# Override the LOG_CLI_ID to change the log file name.
	# Will be set to ARMBIAN_COMMAND if not set after all pre-runs done.
	declare -g ARMBIAN_LOG_CLI_ID

	# Keep a running dict of params/variables. Can't repeat stuff here. Dict.
	declare -g -A ARMBIAN_CLI_RELAUNCH_PARAMS=(["ARMBIAN_RELAUNCHED"]="yes")

	# Keep a running array of config files needed for relaunch.
	declare -g -a ARMBIAN_CLI_RELAUNCH_CONFIGS=()
}
