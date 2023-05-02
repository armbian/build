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

	function json_info_logged() { # logging wrapper
		LOG_SECTION="json_info" do_with_logging json_info_only
	}

	function json_info_only() {
		prepare_python_and_pip # requires HOSTRELEASE

		declare INFO_TOOLS_DIR="${SRC}"/lib/tools/info

		display_alert "Here we go" "generating JSON info :: ${ARMBIAN_COMMAND} " "info"

		# Targets inventory. Will do all-by-all if no targets file is provided.
		declare TARGETS_FILE="${TARGETS_FILE-"${USERPATCHES_PATH}/${TARGETS_FILENAME:-"targets.yaml"}"}" # @TODO: return to targets.yaml one day

		declare BASE_INFO_OUTPUT_DIR="${SRC}/output/info" # Output dir for info

		if [[ "${CLEAN_INFO}" == "yes" ]]; then
			display_alert "Cleaning info output dir" "${BASE_INFO_OUTPUT_DIR}" "info"
			rm -rf "${BASE_INFO_OUTPUT_DIR}"
		fi

		mkdir -p "${BASE_INFO_OUTPUT_DIR}"

		# `gha-template` does not depend on the rest of the info-gatherer, so we can run it first and return.
		if [[ "${ARMBIAN_COMMAND}" == "gha-template" ]]; then
			# If we have userpatches/gha/chunks, run the workflow template utility
			declare user_gha_dir="${USERPATCHES_PATH}/gha"
			declare wf_template_dir="${user_gha_dir}/chunks"
			declare GHA_CONFIG_YAML_FILE="${user_gha_dir}/gha_config.yaml"
			if [[ ! -d "${wf_template_dir}" ]]; then
				exit_with_error "output-gha-workflow-template :: no ${wf_template_dir} directory found"
			fi
			if [[ ! -f "${GHA_CONFIG_YAML_FILE}" ]]; then
				exit_with_error "output-gha-workflow-template :: no ${GHA_CONFIG_YAML_FILE} file found"
			fi

			display_alert "Generating GHA workflow template" "output-gha-workflow-template :: ${wf_template_dir}" "info"
			declare GHA_WORKFLOW_TEMPLATE_OUT_FILE_default="${BASE_INFO_OUTPUT_DIR}/artifact-image-complete-matrix.yml"
			declare GHA_WORKFLOW_TEMPLATE_OUT_FILE="${GHA_WORKFLOW_TEMPLATE_OUT_FILE:-"${GHA_WORKFLOW_TEMPLATE_OUT_FILE_default}"}"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/output-gha-workflow-template.py "${GHA_WORKFLOW_TEMPLATE_OUT_FILE}" "${GHA_CONFIG_YAML_FILE}" "${wf_template_dir}" "${MATRIX_ARTIFACT_CHUNKS:-"17"}" "${MATRIX_IMAGE_CHUNKS:-"16"}"

			display_alert "Done with" "gha-template" "info"
			run_tool_batcat "${GHA_WORKFLOW_TEMPLATE_OUT_FILE}"

			display_alert "Templated workflow file" "${GHA_WORKFLOW_TEMPLATE_OUT_FILE}" "ext"

			return 0 # stop here.
		fi

		### --- inventory --- ###

		declare ALL_BOARDS_ALL_BRANCHES_INVENTORY_FILE="${BASE_INFO_OUTPUT_DIR}/all_boards_all_branches.json"
		declare TARGETS_OUTPUT_FILE="${BASE_INFO_OUTPUT_DIR}/all-targets.json"
		declare IMAGE_INFO_FILE="${BASE_INFO_OUTPUT_DIR}/image-info.json"
		declare IMAGE_INFO_CSV_FILE="${BASE_INFO_OUTPUT_DIR}/image-info.csv"
		declare REDUCED_ARTIFACTS_FILE="${BASE_INFO_OUTPUT_DIR}/artifacts-reduced.json"
		declare ARTIFACTS_INFO_FILE="${BASE_INFO_OUTPUT_DIR}/artifacts-info.json"
		declare ARTIFACTS_INFO_UPTODATE_FILE="${BASE_INFO_OUTPUT_DIR}/artifacts-info-uptodate.json"
		declare OUTDATED_ARTIFACTS_IMAGES_FILE="${BASE_INFO_OUTPUT_DIR}/outdated-artifacts-images.json"

		# Board/branch inventory.
		if [[ ! -f "${ALL_BOARDS_ALL_BRANCHES_INVENTORY_FILE}" ]]; then
			display_alert "Generating board/branch inventory" "all_boards_all_branches.json" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/board-inventory.py ">" "${ALL_BOARDS_ALL_BRANCHES_INVENTORY_FILE}"
		fi

		# @TODO: Release/rootfs inventory?

		# A simplistic all-boards-all-branches target file, for the all-boards-all-branches-targets.json.
		# Then just use the same info-gatherer-image to get the image info.
		# This will be used as database for the targets-compositor, for example to get "all boards+branches that have kernel < 5.0" or "all boards+branches of meson64 family" etc.
		# @TODO: this is a bit heavy; only do it if out-of-date (compared to config/, lib/, extensions/, userpatches/ file mtimes...)

		if [[ "${ARMBIAN_COMMAND}" == "inventory" ]]; then
			display_alert "Done with" "inventory" "info"
			return 0
		fi

		# if TARGETS_FILE does not exist, one will be provided for you, from a template.
		if [[ ! -f "${TARGETS_FILE}" ]]; then
			declare TARGETS_TEMPLATE="${TARGETS_TEMPLATE:-"targets-all-cli.yaml"}"
			display_alert "No targets file found" "using default targets template ${TARGETS_TEMPLATE}" "info"
			TARGETS_FILE="${SRC}/config/templates/${TARGETS_TEMPLATE}"
		else
			display_alert "Using targets file" "${TARGETS_FILE}" "info"
		fi

		if [[ ! -f "${TARGETS_OUTPUT_FILE}" ]]; then
			display_alert "Generating targets inventory" "targets-compositor" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/targets-compositor.py "${ALL_BOARDS_ALL_BRANCHES_INVENTORY_FILE}" "not_yet_releases.json" "${TARGETS_FILE}" ">" "${TARGETS_OUTPUT_FILE}"
		fi

		### Images.

		# The image info extractor.
		if [[ ! -f "${IMAGE_INFO_FILE}" ]]; then
			display_alert "Generating image info" "info-gatherer-image" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/info-gatherer-image.py "${TARGETS_OUTPUT_FILE}" ">" "${IMAGE_INFO_FILE}"
			# if stdin is a terminal...
			if [ -t 0 ]; then
				display_alert "To load the OpenSearch dashboards:" "
					pip3 install opensearch-py # install needed lib to talk to OS
					docker-compose --file tools/dashboards/docker-compose-opensearch.yaml up -d # start up OS in docker-compose
					python3 lib/tools/index-opensearch.py < output/info/image-info.json # index the JSON into OS
					# go check out http://localhost:5601
					docker-compose --file tools/dashboards/docker-compose-opensearch.yaml down # shut down OS when you're done
				" "info"
			fi
		fi

		# convert image info output to CSV for easy import into Google Sheets etc
		if [[ ! -f "${IMAGE_INFO_CSV_FILE}" ]]; then
			display_alert "Generating CSV info" "info.csv" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/json2csv.py "<" "${IMAGE_INFO_FILE}" ">" ${IMAGE_INFO_CSV_FILE}
		fi

		### Artifacts.

		# Reducer: artifacts.
		if [[ ! -f "${REDUCED_ARTIFACTS_FILE}" ]]; then
			display_alert "Reducing info into artifacts" "artifact-reducer" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/artifact-reducer.py "${IMAGE_INFO_FILE}" ">" "${REDUCED_ARTIFACTS_FILE}"
		fi

		# The artifact info extractor.
		if [[ ! -f "${ARTIFACTS_INFO_FILE}" ]]; then
			display_alert "Generating artifact info" "info-gatherer-artifact" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/info-gatherer-artifact.py "${REDUCED_ARTIFACTS_FILE}" ">" "${ARTIFACTS_INFO_FILE}"
		fi

		# Now a mapper, check each OCI coordinate to see if it's up-to-date or not. _cache_ (eternally) the positives, but _never_ cache the negatives.
		# This should ideally use the authentication info and other stuff that ORAS.land would.
		# this is controlled by "CHECK_OCI=yes". most people are not interested in what is or not in the cache when generating a build plan, and it is slow to do.
		if [[ ! -f "${ARTIFACTS_INFO_UPTODATE_FILE}" ]]; then
			display_alert "Gathering OCI info" "mapper-oci-uptodate :: real lookups (CHECK_OCI): ${CHECK_OCI:-"no"}" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/mapper-oci-uptodate.py "${ARTIFACTS_INFO_FILE}" "${CHECK_OCI:-"no"}" ">" "${ARTIFACTS_INFO_UPTODATE_FILE}"
		fi

		# A combinator/reducer: image + artifact; outdated artifacts plus the images that depend on them.
		if [[ ! -f "${OUTDATED_ARTIFACTS_IMAGES_FILE}" ]]; then
			display_alert "Combining image and artifact info" "outdated-artifact-image-reducer" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/outdated-artifact-image-reducer.py "${ARTIFACTS_INFO_UPTODATE_FILE}" "${IMAGE_INFO_FILE}" ">" "${OUTDATED_ARTIFACTS_IMAGES_FILE}"
		fi

		if [[ "${ARMBIAN_COMMAND}" == "targets" ]]; then
			display_alert "Done with" "targets" "info"
			return 0
		fi

		### CI/CD Outputs.

		# Output stage: GHA simplest possible two-matrix worflow.
		# A prepare job running this, prepares two matrixes:
		# One for artifacts. One for images.
		# If the image or artifact is up-to-date, it is still included in matrix, but the job is skipped.
		# If any of the matrixes is bigger than 255 items, an error is generated.
		if [[ "${ARMBIAN_COMMAND}" == "gha-matrix" ]]; then
			if [[ "${CLEAN_MATRIX}" == "yes" ]]; then
				display_alert "Cleaning GHA matrix output" "clean-matrix" "info"
				run_host_command_logged rm -fv "${BASE_INFO_OUTPUT_DIR}"/gha-*-matrix.json
			fi

			display_alert "Generating GHA matrix for artifacts" "output-gha-matrix :: artifacts" "info"
			declare GHA_ALL_ARTIFACTS_JSON_MATRIX_FILE="${BASE_INFO_OUTPUT_DIR}/gha-all-artifacts-matrix.json"
			if [[ ! -f "${GHA_ALL_ARTIFACTS_JSON_MATRIX_FILE}" ]]; then
				run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/output-gha-matrix.py artifacts "${OUTDATED_ARTIFACTS_IMAGES_FILE}" "${MATRIX_ARTIFACT_CHUNKS}" ">" "${GHA_ALL_ARTIFACTS_JSON_MATRIX_FILE}"
			fi
			github_actions_add_output "artifact-matrix" "$(cat "${GHA_ALL_ARTIFACTS_JSON_MATRIX_FILE}")"

			display_alert "Generating GHA matrix for images" "output-gha-matrix :: images" "info"
			declare GHA_ALL_IMAGES_JSON_MATRIX_FILE="${BASE_INFO_OUTPUT_DIR}/gha-all-images-matrix.json"
			if [[ ! -f "${GHA_ALL_IMAGES_JSON_MATRIX_FILE}" ]]; then
				run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/output-gha-matrix.py images "${OUTDATED_ARTIFACTS_IMAGES_FILE}" "${MATRIX_IMAGE_CHUNKS}" ">" "${GHA_ALL_IMAGES_JSON_MATRIX_FILE}"
			fi
			github_actions_add_output "image-matrix" "$(cat "${GHA_ALL_IMAGES_JSON_MATRIX_FILE}")"
		fi

		### a secondary stage, which only makes sense to be run inside GHA, and as such should be split in a different CLI or under a flag.
		if [[ "${ARMBIAN_COMMAND}" == "gha-workflow" ]]; then
			# GHA Workflow output. A delusion. Maybe.
			display_alert "Generating GHA workflow" "output-gha-workflow :: complete" "info"
			declare GHA_WORKFLOW_FILE="${BASE_INFO_OUTPUT_DIR}/gha-workflow.yaml"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/output-gha-workflow.py "${OUTDATED_ARTIFACTS_IMAGES_FILE}" "${GHA_WORKFLOW_FILE}"
		fi

	}

	do_with_default_build json_info_logged

}
