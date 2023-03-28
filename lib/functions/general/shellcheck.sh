#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function shellcheck_debian_control_scripts() {
	declare SEVERITY="${SEVERITY:-"critical"}"
	declare -a params=(--check-sourced --color=always --external-sources --format=tty --shell=bash --wiki-link-count=0)
	case "${SEVERITY}" in
		important)
			params+=("--severity=warning")
			excludes+=(
				"SC2034" # "appears unused" -- bad, but no-one will die of this
			)
			;;

		critical)
			params+=("--severity=warning")
			excludes+=(
				"SC2034" # "appears unused" -- bad, but no-one will die of this
				"SC2207" # "prefer mapfile" -- bad expansion, can lead to trouble; a lot of legacy pre-next code hits this
				"SC2046" # "quote this to prevent word splitting" -- bad expansion, variant 2, a lot of legacy pre-next code hits this
				"SC2086" # "quote this to prevent word splitting" -- bad expansion, variant 3, a lot of legacy pre-next code hits this
				"SC2206" # (warning): Quote to prevent word splitting/globbing, or split robustly with mapfile or read -a.
			)
			;;

		*)
			params=("--severity=${SEVERITY}")
			;;
	esac

	for exclude in "${excludes[@]}"; do
		params+=(--exclude="${exclude}")
	done

	if run_tool_shellcheck "${params[@]}" "${@}"; then
		display_alert "Congrats, no ${SEVERITY}'s detected." "SHELLCHECK" "debug"
		return 0
	else
		display_alert "SHELLCHECK found ${SEVERITY}'s." "SHELLCHECK" "debug"
		return 1
	fi
}

function run_tool_shellcheck() {
	# Default version
	SHELLCHECK_VERSION=${SHELLCHECK_VERSION:-0.9.0} # https://github.com/koalaman/shellcheck/releases

	declare non_cache_dir="/armbian-tools/shellcheck" # To deploy/reuse cached SHELLCHECK in a Docker image.

	if [[ -z "${DIR_SHELLCHECK}" ]]; then
		display_alert "DIR_SHELLCHECK is not set, using default" "SHELLCHECK" "debug"

		if [[ "${deploy_to_non_cache_dir:-"no"}" == "yes" ]]; then
			DIR_SHELLCHECK="${non_cache_dir}" # root directory.
			display_alert "Deploying SHELLCHECK to non-cache dir" "DIR_SHELLCHECK: ${DIR_SHELLCHECK}" "debug"
		else
			if [[ -n "${SRC}" ]]; then
				DIR_SHELLCHECK="${SRC}/cache/tools/shellcheck"
			else
				display_alert "Missing DIR_SHELLCHECK, or SRC fallback" "DIR_SHELLCHECK: ${DIR_SHELLCHECK}; SRC: ${SRC}" "SHELLCHECK" "err"
				return 1
			fi
		fi
	else
		display_alert "DIR_SHELLCHECK is set to ${DIR_SHELLCHECK}" "SHELLCHECK" "debug"
	fi

	mkdir -p "${DIR_SHELLCHECK}"

	declare MACHINE="${BASH_VERSINFO[5]}" SHELLCHECK_OS SHELLCHECK_ARCH
	display_alert "Running SHELLCHECK" "SHELLCHECK version ${SHELLCHECK_VERSION}" "debug"
	MACHINE="${BASH_VERSINFO[5]}"
	case "$MACHINE" in
		*darwin*) SHELLCHECK_OS="darwin" ;;
		*linux*) SHELLCHECK_OS="linux" ;;
		*)
			exit_with_error "unknown os: $MACHINE"
			;;
	esac

	case "$MACHINE" in
		*aarch64*) SHELLCHECK_ARCH="aarch64" ;;
		*x86_64*) SHELLCHECK_ARCH="x86_64" ;;
		*)
			exit_with_error "unknown arch: $MACHINE"
			;;
	esac

	declare SHELLCHECK_FN="shellcheck-v${SHELLCHECK_VERSION}.${SHELLCHECK_OS}.${SHELLCHECK_ARCH}"
	declare SHELLCHECK_FN_TARXZ="${SHELLCHECK_FN}.tar.xz"
	declare DOWN_URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${SHELLCHECK_FN_TARXZ}"
	declare SHELLCHECK_BIN="${DIR_SHELLCHECK}/${SHELLCHECK_FN}"
	declare ACTUAL_VERSION

	# Check if we have a cached version in a Docker image, and copy it over before possibly updating it.
	if [[ "${deploy_to_non_cache_dir:-"no"}" != "yes" && -d "${non_cache_dir}" && ! -f "${SHELLCHECK_BIN}" ]]; then
		display_alert "Using cached SHELLCHECK from Docker image" "SHELLCHECK" "debug"
		run_host_command_logged cp -v "${non_cache_dir}/"* "${DIR_SHELLCHECK}/"
	fi

	if [[ ! -f "${SHELLCHECK_BIN}" ]]; then
		do_with_retries 5 try_download_shellcheck_tooling
	fi
	ACTUAL_VERSION="$("${SHELLCHECK_BIN}" --version | grep "^version" | xargs echo -n)"
	display_alert "Running SHELLCHECK ${ACTUAL_VERSION}" "SHELLCHECK" "debug"

	if [[ "${deploy_to_non_cache_dir:-"no"}" == "yes" ]]; then
		display_alert "Deployed SHELLCHECK to non-cache dir" "DIR_SHELLCHECK: ${DIR_SHELLCHECK}" "debug"
		return 0 # don't actually execute.
	fi

	# Run shellcheck with it
	display_alert "Calling SHELLCHECK" "$*" "debug"
	"${SHELLCHECK_BIN}" "$@"
}

function try_download_shellcheck_tooling() {
	display_alert "MACHINE: ${MACHINE}" "SHELLCHECK" "debug"
	display_alert "Down URL: ${DOWN_URL}" "SHELLCHECK" "debug"
	display_alert "SHELLCHECK_BIN: ${SHELLCHECK_BIN}" "SHELLCHECK" "debug"

	display_alert "Downloading required" "SHELLCHECK tooling${RETRY_FMT_MORE_THAN_ONCE}" "info"
	run_host_command_logged wget --no-verbose --progress=dot:giga -O "${SHELLCHECK_BIN}.tar.xz.tmp" "${DOWN_URL}" || {
		return 1
	}

	run_host_command_logged mv "${SHELLCHECK_BIN}.tar.xz.tmp" "${SHELLCHECK_BIN}.tar.xz"
	run_host_command_logged tar -xf "${SHELLCHECK_BIN}.tar.xz" -C "${DIR_SHELLCHECK}" "shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
	run_host_command_logged mv "${DIR_SHELLCHECK}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "${SHELLCHECK_BIN}"
	run_host_command_logged rm -rf "${DIR_SHELLCHECK}/shellcheck-v${SHELLCHECK_VERSION}" "${SHELLCHECK_BIN}.tar.xz"
	run_host_command_logged chmod +x "${SHELLCHECK_BIN}"
}
