#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function run_tool_oras() {
	# Default version
	ORAS_VERSION=${ORAS_VERSION:-0.16.0} # https://github.com/oras-project/oras/releases
	#ORAS_VERSION=${ORAS_VERSION:-"1.0.0-rc.1"} # https://github.com/oras-project/oras/releases

	declare non_cache_dir="/armbian-tools/oras" # To deploy/reuse cached ORAS in a Docker image.

	if [[ -z "${DIR_ORAS}" ]]; then
		display_alert "DIR_ORAS is not set, using default" "ORAS" "debug"

		if [[ "${deploy_to_non_cache_dir:-"no"}" == "yes" ]]; then
			DIR_ORAS="${non_cache_dir}" # root directory.
			display_alert "Deploying ORAS to non-cache dir" "DIR_ORAS: ${DIR_ORAS}" "debug"
		else
			if [[ -n "${SRC}" ]]; then
				DIR_ORAS="${SRC}/cache/tools/oras"
			else
				display_alert "Missing DIR_ORAS, or SRC fallback" "DIR_ORAS: ${DIR_ORAS}; SRC: ${SRC}" "ORAS" "err"
				return 1
			fi
		fi
	else
		display_alert "DIR_ORAS is set to ${DIR_ORAS}" "ORAS" "debug"
	fi

	mkdir -p "${DIR_ORAS}"

	declare MACHINE="${BASH_VERSINFO[5]}" ORAS_OS ORAS_ARCH
	display_alert "Running ORAS" "ORAS version ${ORAS_VERSION}" "debug"
	MACHINE="${BASH_VERSINFO[5]}"
	case "$MACHINE" in
		*darwin*) ORAS_OS="darwin" ;;
		*linux*) ORAS_OS="linux" ;;
		*)
			exit_with_error "unknown os: $MACHINE"
			;;
	esac

	case "$MACHINE" in
		*aarch64*) ORAS_ARCH="arm64" ;;
		*x86_64*) ORAS_ARCH="amd64" ;;
		*)
			exit_with_error "unknown arch: $MACHINE"
			;;
	esac

	declare ORAS_FN="oras_${ORAS_VERSION}_${ORAS_OS}_${ORAS_ARCH}"
	declare ORAS_FN_TARXZ="${ORAS_FN}.tar.gz"
	declare DOWN_URL="https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/${ORAS_FN_TARXZ}"
	declare ORAS_BIN="${DIR_ORAS}/${ORAS_FN}"
	declare ACTUAL_VERSION

	# Check if we have a cached version in a Docker image, and copy it over before possibly updating it.
	if [[ "${deploy_to_non_cache_dir:-"no"}" != "yes" && -d "${non_cache_dir}" && ! -f "${ORAS_BIN}" ]]; then
		display_alert "Using cached ORAS from Docker image" "ORAS" "debug"
		run_host_command_logged cp -r "${non_cache_dir}/"* "${DIR_ORAS}/"
	fi

	if [[ ! -f "${ORAS_BIN}" ]]; then
		do_with_retries 5 try_download_oras_tooling
	fi
	ACTUAL_VERSION="$("${ORAS_BIN}" version | grep "^Version" | xargs echo -n)"
	display_alert "Running ORAS ${ACTUAL_VERSION}" "ORAS" "debug"

	if [[ "${deploy_to_non_cache_dir:-"no"}" == "yes" ]]; then
		display_alert "Deployed ORAS to non-cache dir" "DIR_ORAS: ${DIR_ORAS}" "debug"
		return 0 # don't actually execute.
	fi

	# Run oras, possibly with retries...
	if [[ "${retries:-1}" -gt 1 ]]; then
		display_alert "Calling ORAS with retries ${retries}" "$*" "debug"
		sleep_seconds="30" do_with_retries "${retries}" "${ORAS_BIN}" "$@"
	else
		# If any parameters passed, call ORAS, otherwise exit. We call it this way (sans-parameters) early to prepare ORAS tooling.
		if [[ $# -eq 0 ]]; then
			display_alert "No parameters passed to ORAS" "ORAS" "debug"
			return 0
		fi

		display_alert "Calling ORAS" "$*" "debug"
		"${ORAS_BIN}" "$@"
	fi
}

function try_download_oras_tooling() {
	display_alert "MACHINE: ${MACHINE}" "ORAS" "debug"
	display_alert "Down URL: ${DOWN_URL}" "ORAS" "debug"
	display_alert "ORAS_BIN: ${ORAS_BIN}" "ORAS" "debug"

	display_alert "Downloading required" "ORAS tooling${RETRY_FMT_MORE_THAN_ONCE}" "info"
	run_host_command_logged wget --no-verbose --progress=dot:giga -O "${ORAS_BIN}.tar.gz.tmp" "${DOWN_URL}" || {
		return 1
	}
	run_host_command_logged mv "${ORAS_BIN}.tar.gz.tmp" "${ORAS_BIN}.tar.gz"
	run_host_command_logged tar -xf "${ORAS_BIN}.tar.gz" -C "${DIR_ORAS}" "oras"
	run_host_command_logged rm -rf "${ORAS_BIN}.tar.gz"
	run_host_command_logged mv "${DIR_ORAS}/oras" "${ORAS_BIN}"
	run_host_command_logged chmod +x "${ORAS_BIN}"
}

function oras_push_artifact_file() {
	declare image_full_oci="${1}" # Something like "ghcr.io/rpardini/armbian-git-shallow/kernel-git:latest"
	declare upload_file="${2}"    # Absolute path to the file to upload including the path and name
	declare description="${3:-"missing description"}"
	declare upload_file_base_path upload_file_name
	display_alert "Pushing ${upload_file}" "ORAS to ${image_full_oci}" "info"

	declare extra_params=("--verbose")
	oras_add_param_plain_http
	oras_add_param_insecure
	extra_params+=("--annotation" "org.opencontainers.image.description=${description}")

	# make sure file exists
	if [[ ! -f "${upload_file}" ]]; then
		display_alert "File not found: ${upload_file}" "ORAS upload" "err"
		return 1
	fi

	# split the path and the filename
	upload_file_base_path="$(dirname "${upload_file}")"
	upload_file_name="$(basename "${upload_file}")"
	display_alert "upload_file_base_path: ${upload_file_base_path}" "ORAS upload" "debug"
	display_alert "upload_file_name: ${upload_file_name}" "ORAS upload" "debug"

	pushd "${upload_file_base_path}" &> /dev/null || exit_with_error "Failed to pushd to ${upload_file_base_path} - ORAS upload"
	retries=10 run_tool_oras push "${extra_params[@]}" "${image_full_oci}" "${upload_file_name}:application/vnd.unknown.layer.v1+tar"
	popd &> /dev/null || exit_with_error "Failed to popd" "ORAS upload"
	return 0
}

# Outer scope: oras_has_manifest (yes/no) and oras_manifest_json (json)
function oras_get_artifact_manifest() {
	declare image_full_oci="${1}" # Something like "ghcr.io/rpardini/armbian-git-shallow/kernel-git:latest"
	display_alert "Getting ORAS manifest" "ORAS manifest from ${image_full_oci}" "info"

	declare extra_params=("--verbose")
	oras_add_param_plain_http
	oras_add_param_insecure

	oras_has_manifest="no"
	# Gotta capture the output & if it failed...
	oras_manifest_json="$(run_tool_oras manifest fetch "${extra_params[@]}" "${image_full_oci}")" && oras_has_manifest="yes" || oras_has_manifest="no"
	display_alert "oras_has_manifest after: ${oras_has_manifest}" "ORAS manifest yes/no" "debug"
	display_alert "oras_manifest_json after: ${oras_manifest_json}" "ORAS manifest json" "debug"

	# if it worked, parse some basic info using jq
	if [[ "${oras_has_manifest}" == "yes" ]]; then
		oras_manifest_description="$(echo "${oras_manifest_json}" | jq -r '.annotations."org.opencontainers.image.description"')"
		display_alert "oras_manifest_description: ${oras_manifest_description}" "ORAS oras_manifest_description" "debug"
	fi

	return 0
}

# oras pull is very hard to work with, since we don't determine the filename until after the download.
function oras_pull_artifact_file() {
	declare image_full_oci="${1}" # Something like "ghcr.io/rpardini/armbian-git-shallow/kernel-git:latest"
	declare target_dir="${2}"     # temporary directory we'll use for the download to workaround oras being maniac
	declare target_fn="${3}"

	declare extra_params=("--verbose")
	oras_add_param_plain_http
	oras_add_param_insecure

	declare full_temp_dir="${target_dir}/${target_fn}.oras.pull.tmp"
	declare full_tmp_file_path="${full_temp_dir}/${target_fn}"
	run_host_command_logged mkdir -p "${full_temp_dir}"

	# @TODO: this needs retries...
	pushd "${full_temp_dir}" &> /dev/null || exit_with_error "Failed to pushd to ${full_temp_dir} - ORAS download"
	retries=3 run_tool_oras pull "${extra_params[@]}" "${image_full_oci}"
	popd &> /dev/null || exit_with_error "Failed to popd - ORAS download"

	# sanity check; did we get the file we expected?
	if [[ ! -f "${full_tmp_file_path}" ]]; then
		exit_with_error "File not found after ORAS pull: ${full_tmp_file_path} - ORAS download"
		return 1
	fi

	# move the file to the target directory
	run_host_command_logged mv "${full_tmp_file_path}" "${target_dir}"

	# remove the temp directory
	run_host_command_logged rm -rf "${full_temp_dir}"
}

function oras_add_param_plain_http() {
	# if image_full_oci contains ":5000/", add --plain-http; to make easy to run self-hosted registry
	if [[ "${image_full_oci}" == *":5000/"* ]]; then
		display_alert "Adding --plain-http to ORAS" "ORAS to insecure registry" "warn"
		extra_params+=("--plain-http")
	fi
}

function oras_add_param_insecure() {
	if [[ ${IS_A_RETRY} -gt 0 ]]; then
		display_alert "Retrying, adding --insecure to ORAS" "ORAS to insecure registry on retry" "warn"
		extra_params+=("--insecure")
	fi
}
