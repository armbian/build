function cli_config_dump_pre_run() {
	declare -g CONFIG_DEFS_ONLY='yes'
}

function cli_config_dump_run() {
	# configuration etc - it initializes the extension manager
	do_capturing_defs config_and_remove_useless < /dev/null # this sets CAPTURED_VARS; the < /dev/null is take away the terminal from stdin
	echo "${CAPTURED_VARS}"                                 # to stdout!
}

function config_and_remove_useless() {
	do_logging=no prepare_and_config_main_build_single # avoid logging during configdump; it's useless
	unset FINALDEST
	unset FINAL_HOST_DEPS
	unset HOOK_ORDER HOOK_POINT HOOK_POINT_TOTAL_FUNCS
	unset REPO_CONFIG REPO_STORAGE
	unset DEB_STORAGE
	unset RKBIN_DIR
	unset ROOTPWD
}
