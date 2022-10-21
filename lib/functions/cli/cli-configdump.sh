function cli_config_dump_pre_run() {
	declare -g CONFIG_DEFS_ONLY='yes'
}

function cli_config_dump_run() {
	# configuration etc - it initializes the extension manager
	do_capturing_defs prepare_and_config_main_build_single # this sets CAPTURED_VARS
	echo "${CAPTURED_VARS}" # to stdout!
}
