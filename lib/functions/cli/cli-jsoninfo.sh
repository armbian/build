function cli_json_info_pre_run() {
	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_json_info_run() {
	display_alert "Generating JSON info" "for all boards; wait" "info"

	obtain_and_check_host_release_and_arch # sets HOSTRELEASE
	prepare_python_and_pip # requires HOSTRELEASE

	# The info extractor itself...
	run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${SRC}"/lib/tools/info.py ">" "${SRC}/output/info.json"

	# Also convert output to CSV for easy import into Google Sheets etc
	run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${SRC}"/lib/tools/json2csv.py "<" "${SRC}/output/info.json" ">" "${SRC}/output/info.csv"
}
