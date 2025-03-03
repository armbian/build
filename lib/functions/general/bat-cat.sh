#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function run_tool_batcat() {
	# Default version
	BATCAT_VERSION=${BATCAT_VERSION:-0.25.0} # https://github.com/sharkdp/bat/releases

	declare non_cache_dir="/armbian-tools/batcat" # To deploy/reuse cached batcat in a Docker image.

	if [[ -z "${DIR_BATCAT}" ]]; then
		display_alert "DIR_BATCAT is not set, using default" "batcat" "debug"

		if [[ "${deploy_to_non_cache_dir:-"no"}" == "yes" ]]; then
			DIR_BATCAT="${non_cache_dir}" # root directory.
			display_alert "Deploying batcat to non-cache dir" "DIR_BATCAT: ${DIR_BATCAT}" "debug"
		else
			if [[ -n "${SRC}" ]]; then
				DIR_BATCAT="${SRC}/cache/tools/batcat"
			else
				display_alert "Missing DIR_BATCAT, or SRC fallback" "DIR_BATCAT: ${DIR_BATCAT}; SRC: ${SRC}" "batcat" "err"
				return 1
			fi
		fi
	else
		display_alert "DIR_BATCAT is set to ${DIR_BATCAT}" "batcat" "debug"
	fi

	mkdir -p "${DIR_BATCAT}"

	declare MACHINE="${BASH_VERSINFO[5]}" BATCAT_OS BATCAT_ARCH
	display_alert "Running batcat" "batcat version ${BATCAT_VERSION}" "debug"
	MACHINE="${BASH_VERSINFO[5]}"

	case "$MACHINE" in
		*x86_64-*-linux-gnu*) BATCAT_ARCH_OS="x86_64-unknown-linux-gnu" ;;
		*aarch64-*-linux-gnu*) BATCAT_ARCH_OS="aarch64-unknown-linux-gnu" ;;
		*x86_64-apple-darwin*) BATCAT_ARCH_OS="x86_64-apple-darwin" ;;
		*riscv64*)
			# check https://github.com/sharkdp/bat in the future, build might be possible
			display_alert "No RISC-V riscv64 support for batcat" "batcat will not run" "wrn"
			return 0
			;;
		*)
			exit_with_error "unknown os/arch for batcat download: '$MACHINE'"
			;;
	esac

	# linux amd64   https://github.com/sharkdp/bat/releases/download/v0.23.0/bat-v0.23.0-x86_64-unknown-linux-gnu.tar.gz
	# linux aarch64 https://github.com/sharkdp/bat/releases/download/v0.23.0/bat-v0.23.0-aarch64-unknown-linux-gnu.tar.gz
	# linux armhf   https://github.com/sharkdp/bat/releases/download/v0.23.0/bat-v0.23.0-arm-unknown-linux-gnueabihf.tar.gz
	# darwin amd64  https://github.com/sharkdp/bat/releases/download/v0.23.0/bat-v0.23.0-x86_64-apple-darwin.tar.gz
	# darwin arm64  <missing>

	declare BATCAT_FN="bat-v${BATCAT_VERSION}-${BATCAT_ARCH_OS}"
	declare BATCAT_FN_TARXZ="${BATCAT_FN}.tar.gz"
	declare DOWN_URL="${GITHUB_SOURCE:-"https://github.com"}/sharkdp/bat/releases/download/v${BATCAT_VERSION}/${BATCAT_FN_TARXZ}"
	declare BATCAT_BIN="${DIR_BATCAT}/${BATCAT_FN}-bin"
	declare ACTUAL_VERSION

	# Check if we have a cached version in a Docker image, and copy it over before possibly updating it.
	if [[ "${deploy_to_non_cache_dir:-"no"}" != "yes" && -d "${non_cache_dir}" && ! -f "${BATCAT_BIN}" ]]; then
		display_alert "Using cached batcat from Docker image" "batcat" "debug"
		run_host_command_logged cp -rv "${non_cache_dir}/"* "${DIR_BATCAT}/"
	fi

	if [[ ! -f "${BATCAT_BIN}" ]]; then
		# @TODO: do_with_retries 5
		try_download_batcat_tooling
	fi

	# set pipefail in the subshell, so grep does not hide the actual command's result
	ACTUAL_VERSION="$(set -o pipefail && "${BATCAT_BIN}" --version | grep "^bat" | xargs echo -n)"
	display_alert "Running batcat ${ACTUAL_VERSION}" "batcat" "debug"

	# If no 'syntaxes.bin' in the cache dir, prepare it...
	if [[ ! -f "${DIR_BATCAT}/cache/syntaxes.bin" ]]; then
		display_alert "Preparing batcat cache" "batcat" "debug"
		# Problem: "${SRC}/cache" might exist, and confuses batcat into thinking it's a file argument, instead of the "cache" command.
		# Workaround: use a subshell to cd into "${SRC}/.tmp" and run from there.
		run_host_command_logged cd "${SRC}/.tmp" ";" BAT_CONFIG_DIR="${DIR_BATCAT}/config" BAT_CACHE_PATH="${DIR_BATCAT}/cache" "${BATCAT_BIN}" cache --build
	fi

	if [[ "${deploy_to_non_cache_dir:-"no"}" == "yes" ]]; then
		display_alert "Deployed batcat to non-cache dir" "DIR_BATCAT: ${DIR_BATCAT}" "debug"
		return 0 # don't actually execute.
	fi

	# If any parameters passed, call ORAS, otherwise exit. We call it this way (sans-parameters) early to prepare ORAS tooling.
	if [[ $# -eq 0 ]]; then
		display_alert "No parameters passed to batcat" "batcat" "debug"
		return 0
	fi

	declare -i bat_cat_columns=$(("${COLUMNS:-"120"}" - 20)) # A bit shorter since might be prefixed by emoji etc
	if [[ "${bat_cat_columns}" -lt 60 ]]; then               # but lever less than 60
		bat_cat_columns=60
	fi
	case "${background_dark_or_light}" in
		dark) declare bat_cat_theme="Dracula" ;;
		*) declare bat_cat_theme="ansi" ;;
	esac
	display_alert "Calling batcat" "COLUMNS: ${bat_cat_columns} | $*" "debug"
	BAT_CONFIG_DIR="${DIR_BATCAT}/config" BAT_CACHE_PATH="${DIR_BATCAT}/cache" "${BATCAT_BIN}" --theme "${bat_cat_theme}" --paging=never --force-colorization --wrap auto --terminal-width "${bat_cat_columns}" "$@"
	wait_for_disk_sync "after running batcat"
}

function try_download_batcat_tooling() {
	display_alert "MACHINE: ${MACHINE}" "batcat" "debug"
	display_alert "Down URL: ${DOWN_URL}" "batcat" "debug"
	display_alert "BATCAT_BIN: ${BATCAT_BIN}" "batcat" "debug"
	display_alert "BATCAT_FN: ${BATCAT_FN}" "batcat" "debug"

	display_alert "Downloading required" "batcat tooling${RETRY_FMT_MORE_THAN_ONCE}" "info"
	run_host_command_logged wget --no-verbose --progress=dot:giga -O "${BATCAT_BIN}.tar.gz.tmp" "${DOWN_URL}" || {
		return 1
	}
	run_host_command_logged mv "${BATCAT_BIN}.tar.gz.tmp" "${BATCAT_BIN}.tar.gz"
	run_host_command_logged tar -xf "${BATCAT_BIN}.tar.gz" -C "${DIR_BATCAT}" "${BATCAT_FN}/bat"
	run_host_command_logged rm -rf "${BATCAT_BIN}.tar.gz"

	# EXTRA: get more syntaxes for batcat. We need Debian syntax for CONTROL files, etc.
	run_host_command_logged wget --no-verbose --progress=dot:giga -O "${DIR_BATCAT}/sublime-debian.tar.gz.tmp" "${GITHUB_SOURCE:-"https://github.com"}/barnumbirr/sublime-debian/archive/refs/heads/master.tar.gz"
	run_host_command_logged mkdir -p "${DIR_BATCAT}/temp-debian-syntax"
	run_host_command_logged tar -xzf "${DIR_BATCAT}/sublime-debian.tar.gz.tmp" -C "${DIR_BATCAT}/temp-debian-syntax" sublime-debian-master/Syntaxes

	# Prepare the config and cache dir... clean it off and begin anew everytime
	run_host_command_logged rm -rf "${DIR_BATCAT}/config" "${DIR_BATCAT}/cache"
	run_host_command_logged mkdir -p "${DIR_BATCAT}/config" "${DIR_BATCAT}/cache" "${DIR_BATCAT}/config/syntaxes"

	# Move the sublime-debian syntaxes into the final syntaxes dir
	run_host_command_logged mv "${DIR_BATCAT}/temp-debian-syntax/sublime-debian-master/Syntaxes"/* "${DIR_BATCAT}/config/syntaxes/"

	# Delete the temps for sublime-debian
	run_host_command_logged rm -rf "${DIR_BATCAT}/temp-debian-syntax" "${DIR_BATCAT}/sublime-debian.tar.gz.tmp"

	# Finish up, mark done.
	run_host_command_logged mv "${DIR_BATCAT}/${BATCAT_FN}/bat" "${BATCAT_BIN}"
	run_host_command_logged rm -rf "${DIR_BATCAT}/${BATCAT_FN}"
	run_host_command_logged chmod +x -v "${BATCAT_BIN}"
}
