function cli_config_dump_pre_run() {
	declare -g CONFIG_DEFS_ONLY='yes'
	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_config_dump_run() {
	# configuration etc - it initializes the extension manager
	do_capturing_defs prepare_and_config_main_build_single # this sets CAPTURED_VARS
	echo "${CAPTURED_VARS}"                                # to stdout!
}
