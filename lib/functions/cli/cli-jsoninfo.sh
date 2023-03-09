#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function cli_json_info_pre_run() {
	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_json_info_run() {
	display_alert "Generating JSON info" "for all boards; wait" "info"

	prep_conf_main_minimal_ni

	function json_info_only() {
		prepare_python_and_pip # requires HOSTRELEASE

		# The info extractor itself...
		run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${SRC}"/lib/tools/info.py ">" "${SRC}/output/info.json"

		# Also convert output to CSV for easy import into Google Sheets etc
		run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${SRC}"/lib/tools/json2csv.py "<" "${SRC}/output/info.json" ">" "${SRC}/output/info.csv"
	}

	do_with_default_build do_with_logging json_info_only

	display_alert "JSON info generated" "in output/info.json" "info"
	display_alert "CSV info generated" "in output/info.csv" "info"
	display_alert "To load the OpenSearch dashboards:" "
		pip3 install opensearch-py # install needed lib to talk to OS
		docker-compose --file tools/dashboards/docker-compose-opensearch.yaml up -d # start up OS in docker-compose
		python3 lib/tools/index-opensearch.py < output/info.json # index the info.json into OS
		# go check out http://localhost:5601
		docker-compose --file tools/dashboards/docker-compose-opensearch.yaml down # shut down OS when you're done
	" "info"

}
