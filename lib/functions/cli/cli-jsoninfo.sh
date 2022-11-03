function cli_json_info_pre_run() {
	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_json_info_run() {
	display_alert "Generating JSON info" "for all boards; wait" "info"

	# So call a Python launcher.
	# @TODO: this works without ti right now, since all the python stuff works with no external packages
	# - python debian packages hostdeps? (-dev, -pip, virtualenv, etc)
	# - run the virtualenv (messy?)

	# The info extractor itself...
	run_host_command_logged python3 "${SRC}"/lib/tools/info.py ">" "${SRC}/output/info.json"

	# Also convert output to CSV for easy import into Google Sheets etc
	run_host_command_logged python3 "${SRC}"/lib/tools/json2csv.py "<" "${SRC}/output/info.json" ">" "${SRC}/output/info.csv"
}
