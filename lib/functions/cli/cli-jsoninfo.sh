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
		declare TARGETS_FILE="${TARGETS_FILE-"${USERPATCHES_PATH}/${TARGETS_FILENAME:-"targets.yaml"}"}"

		declare BASE_INFO_OUTPUT_DIR="${SRC}/output/info" # Output dir for info

		if [[ "${CLEAN_INFO:-"yes"}" != "no" ]]; then
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

		# debs-to-repo-download is also isolated from the rest. It does depend on the debs-to-repo-info, but that's prepared beforehand in a standard pipeline run.
		if [[ "${ARMBIAN_COMMAND}" == "debs-to-repo-download" ]]; then
			display_alert "Downloading debs" "debs-to-repo-download" "info"
			declare DEBS_TO_REPO_INFO_FILE="${BASE_INFO_OUTPUT_DIR}/debs-to-repo-info.json"
			if [[ ! -f "${DEBS_TO_REPO_INFO_FILE}" ]]; then
				exit_with_error "debs-to-repo-download :: no ${DEBS_TO_REPO_INFO_FILE} file found; did you restore the pipeline artifacts correctly?"
			fi
			declare DEBS_OUTPUT_DIR="${DEB_STORAGE}" # this is different depending if BETA=yes (output/debs-beta) or not (output/debs)
			display_alert "Downloading debs to" "${DEBS_OUTPUT_DIR}" "info"
			export PARALLEL_DOWNLOADS_WORKERS="${PARALLEL_DOWNLOADS_WORKERS}"
			run_host_command_logged mkdir -pv "${DEBS_OUTPUT_DIR}"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/download-debs.py "${DEBS_TO_REPO_INFO_FILE}" "${DEBS_OUTPUT_DIR}"

			display_alert "Done with" "debs-to-repo-download" "ext"

			return 0 # stop here.
		fi

		# debs-to-repo-download is also isolated from the rest. It does depend on the debs-to-repo-info, but that's prepared beforehand in a standard pipeline run.
		if [[ "${ARMBIAN_COMMAND}" == "debs-to-repo-reprepro" ]]; then
			display_alert "Generating rerepro publishing script" "debs-to-repo-reprepro" "info"
			declare DEBS_TO_REPO_INFO_FILE="${BASE_INFO_OUTPUT_DIR}/debs-to-repo-info.json"
			if [[ ! -f "${DEBS_TO_REPO_INFO_FILE}" ]]; then
				exit_with_error "debs-to-repo-reprepro :: no ${DEBS_TO_REPO_INFO_FILE} file found; did you restore the pipeline artifacts correctly?"
			fi
			declare OUTPUT_INFO_REPREPRO_DIR="${BASE_INFO_OUTPUT_DIR}/reprepro"
			declare OUTPUT_INFO_REPREPRO_CONF_DIR="${OUTPUT_INFO_REPREPRO_DIR}/conf"
			run_host_command_logged mkdir -pv "${OUTPUT_INFO_REPREPRO_DIR}" "${OUTPUT_INFO_REPREPRO_CONF_DIR}"

			# Export params so Python can see them
			export REPO_GPG_KEYID="${REPO_GPG_KEYID}"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/repo-reprepro.py "${DEBS_TO_REPO_INFO_FILE}" "${OUTPUT_INFO_REPREPRO_DIR}" "${OUTPUT_INFO_REPREPRO_CONF_DIR}"

			display_alert "Done with" "debs-to-repo-reprepro" "ext"

			return 0 # stop here.
		fi

		### --- inventory --- ###

		declare ALL_USERSPACE_INVENTORY_FILE="${BASE_INFO_OUTPUT_DIR}/all_userspace_inventory.json"
		declare ALL_BOARDS_ALL_BRANCHES_INVENTORY_FILE="${BASE_INFO_OUTPUT_DIR}/all_boards_all_branches.json"
		declare TARGETS_OUTPUT_FILE="${BASE_INFO_OUTPUT_DIR}/all-targets.json"
		declare IMAGE_INFO_FILE="${BASE_INFO_OUTPUT_DIR}/image-info.json"
		declare IMAGE_INFO_CSV_FILE="${BASE_INFO_OUTPUT_DIR}/image-info.csv"
		declare REDUCED_ARTIFACTS_FILE="${BASE_INFO_OUTPUT_DIR}/artifacts-reduced.json"
		declare ARTIFACTS_INFO_FILE="${BASE_INFO_OUTPUT_DIR}/artifacts-info.json"
		declare ARTIFACTS_INFO_UPTODATE_FILE="${BASE_INFO_OUTPUT_DIR}/artifacts-info-uptodate.json"
		declare OUTDATED_ARTIFACTS_IMAGES_FILE="${BASE_INFO_OUTPUT_DIR}/outdated-artifacts-images.json"

		# Userspace inventory: RELEASES, and DESKTOPS and their possible ARCH'es, names, and support status.
		if [[ ! -f "${ALL_USERSPACE_INVENTORY_FILE}" ]]; then
			display_alert "Generating userspace inventory" "all_userspace_inventory.json" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/userspace-inventory.py ">" "${ALL_USERSPACE_INVENTORY_FILE}"
		fi

		# Board/branch inventory.
		if [[ ! -f "${ALL_BOARDS_ALL_BRANCHES_INVENTORY_FILE}" ]]; then
			display_alert "Generating board/branch inventory" "all_boards_all_branches.json" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/board-inventory.py ">" "${ALL_BOARDS_ALL_BRANCHES_INVENTORY_FILE}"
		fi

		if [[ "${ARMBIAN_COMMAND}" == "inventory" ]]; then
			display_alert "Done with" "inventory" "info"
			return 0
		fi

		# if TARGETS_FILE does not exist, one will be provided for you, from a template.
		if [[ ! -f "${TARGETS_FILE}" ]]; then
			declare TARGETS_TEMPLATE="${TARGETS_TEMPLATE:-"targets-default.yaml"}"
			display_alert "No targets file found" "using default targets template ${TARGETS_TEMPLATE}" "warn"
			TARGETS_FILE="${SRC}/config/templates/${TARGETS_TEMPLATE}"
		else
			display_alert "Using targets file" "${TARGETS_FILE}" "warn"
		fi

		if [[ ! -f "${TARGETS_OUTPUT_FILE}" ]]; then
			display_alert "Generating targets inventory" "targets-compositor" "info"
			export TARGETS_BETA="${BETA}"                             # Read by the Python script, and injected into every target as "BETA=" param.
			export TARGETS_REVISION="${REVISION}"                     # Read by the Python script, and injected into every target as "REVISION=" param.
			export TARGETS_FILTER_INCLUDE="${TARGETS_FILTER_INCLUDE}" # Read by the Python script; used to "only include" targets that match the given string.
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/targets-compositor.py "${ALL_BOARDS_ALL_BRANCHES_INVENTORY_FILE}" "${ALL_USERSPACE_INVENTORY_FILE}" "${TARGETS_FILE}" ">" "${TARGETS_OUTPUT_FILE}"
			unset TARGETS_BETA
			unset TARGETS_REVISION
			unset TARGETS_FILTER_INCLUDE
		fi

		if [[ "${ARMBIAN_COMMAND}" == "targets-composed" ]]; then
			display_alert "Done with" "targets-dashboard" "info"
			return 0
		fi

		### Images.

		# The image info extractor.
		if [[ ! -f "${IMAGE_INFO_FILE}" ]]; then
			display_alert "Generating image info" "info-gatherer-image" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/info-gatherer-image.py "${TARGETS_OUTPUT_FILE}" ">" "${IMAGE_INFO_FILE}"
		fi

		# convert image info output to CSV for easy import into Google Sheets etc
		if [[ ! -f "${IMAGE_INFO_CSV_FILE}" ]]; then
			display_alert "Generating CSV info" "info.csv" "info"
			run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/json2csv.py "<" "${IMAGE_INFO_FILE}" ">" ${IMAGE_INFO_CSV_FILE}
		fi

		if [[ "${ARMBIAN_COMMAND}" == "targets-dashboard" ]]; then
			display_alert "To load the OpenSearch dashboards:" "
				pip3 install opensearch-py # install needed lib to talk to OpenSearch
				sysctl -w vm.max_map_count=262144 # raise limited needed by OpenSearch
				docker-compose --file tools/dashboards/docker-compose-opensearch.yaml up -d # start up OS in docker-compose
				python3 lib/tools/index-opensearch.py < output/info/image-info.json # index the JSON into OpenSearch
				# go check out http://localhost:5601
				docker-compose --file tools/dashboards/docker-compose-opensearch.yaml down # shut down OpenSearch when you're done
				" "info"
			display_alert "Done with" "targets-dashboard" "info"
			return 0
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

		# output stage: deploy debs to repo.
		# Artifacts-to-repo output. Takes all artifacts, and produces info necessary for:
		# 1) getting the artifact from OCI only (not build it)
		# 2) getting the list of .deb's to be published to the repo for that artifact
		display_alert "Generating deb-to-repo JSON output" "output-debs-to-repo-json" "info"
		# This produces debs-to-repo-info.json
		run_host_command_logged "${PYTHON3_VARS[@]}" "${PYTHON3_INFO[BIN]}" "${INFO_TOOLS_DIR}"/output-debs-to-repo-json.py "${BASE_INFO_OUTPUT_DIR}" "${OUTDATED_ARTIFACTS_IMAGES_FILE}"
		if [[ "${ARMBIAN_COMMAND}" == "debs-to-repo-json" ]]; then
			display_alert "Done with" "output-debs-to-repo-json" "ext"
			return 0
		fi

		# Output stage: GHA simplest possible two-matrix worflow.
		# A prepare job running this, prepares two matrixes:
		# One for artifacts. One for images.
		# If the image or artifact is up-to-date, it is still included in matrix, but the job is skipped.
		# If any of the matrixes is bigger than 255 items, an error is generated.
		if [[ "${ARMBIAN_COMMAND}" == "gha-matrix" ]]; then
			if [[ "${CLEAN_MATRIX:-"yes"}" != "no" ]]; then
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
				# export env vars used by the Python script.
				export SKIP_IMAGES="${SKIP_IMAGES:-"no"}"
				export IMAGES_ONLY_OUTDATED_ARTIFACTS="${IMAGES_ONLY_OUTDATED_ARTIFACTS:-"no"}"
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
