#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

SHELLCHECK_VERSION=${SHELLCHECK_VERSION:-0.9.0} # https://github.com/koalaman/shellcheck/releases

SRC="$(
	cd "$(dirname "$0")/../.."
	pwd -P
)"
echo "SRC: ${SRC}"

DIR_SHELLCHECK="${SRC}/cache/tools/shellcheck"
mkdir -p "${DIR_SHELLCHECK}"

MACHINE="${BASH_VERSINFO[5]}"
case "$MACHINE" in
	*darwin*) SHELLCHECK_OS="darwin" ;;
	*linux*) SHELLCHECK_OS="linux" ;;
	*)
		echo "unknown os: $MACHINE"
		exit 3
		;;
esac

case "$MACHINE" in
	*aarch64*) SHELLCHECK_ARCH="aarch64" ;;
	*x86_64*) SHELLCHECK_ARCH="x86_64" ;;
	*)
		echo "unknown arch: $MACHINE"
		exit 2
		;;
esac

# https://github.com/koalaman/shellcheck/releases/download/v0.8.0/shellcheck-v0.8.0.darwin.x86_64.tar.xz
# https://github.com/koalaman/shellcheck/releases/download/v0.8.0/shellcheck-v0.8.0.linux.aarch64.tar.xz
# https://github.com/koalaman/shellcheck/releases/download/v0.8.0/shellcheck-v0.8.0.linux.x86_64.tar.xz

SHELLCHECK_FN="shellcheck-v${SHELLCHECK_VERSION}.${SHELLCHECK_OS}.${SHELLCHECK_ARCH}"
SHELLCHECK_FN_TARXZ="${SHELLCHECK_FN}.tar.xz"
DOWN_URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${SHELLCHECK_FN_TARXZ}"
SHELLCHECK_BIN="${DIR_SHELLCHECK}/${SHELLCHECK_FN}"

if [[ ! -f "${SHELLCHECK_BIN}" ]]; then
	echo "Cache miss, downloading..."
	echo "MACHINE: ${MACHINE}"
	echo "Down URL: ${DOWN_URL}"
	echo "SHELLCHECK_BIN: ${SHELLCHECK_BIN}"
	wget -O "${SHELLCHECK_BIN}.tar.xz" "${DOWN_URL}"
	tar -xf "${SHELLCHECK_BIN}.tar.xz" -C "${DIR_SHELLCHECK}" "shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
	mv -v "${DIR_SHELLCHECK}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "${SHELLCHECK_BIN}"
	rm -rf "${DIR_SHELLCHECK}/shellcheck-v${SHELLCHECK_VERSION}" "${SHELLCHECK_BIN}.tar.xz"
	chmod +x "${SHELLCHECK_BIN}"
fi
ACTUAL_VERSION="$("${SHELLCHECK_BIN}" --version | grep "^version")"

function calculate_params_for_severity() {
	declare SEVERITY="${SEVERITY:-"critical"}"

	params+=(--check-sourced --color=always --external-sources --format=tty --shell=bash)
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
			params+=("--severity=${SEVERITY}")
			;;
	esac

	for exclude in "${excludes[@]}"; do
		params+=(--exclude="${exclude}")
	done
}

declare -a problems=()

# formats:
# checkstyle -- some XML format
# gcc - one per line, compact references; does not show the source
# tty - default for checkstyle

cd "${SRC}" || exit 3

# config/sources errors
SEVERITY="error"
declare -a params=()
calculate_params_for_severity
declare -a config_files=()
declare -a config_source_files=()
declare -a config_board_files=()
mapfile -t config_source_files < <(find "${SRC}/config/sources" -type f -name "*.inc" -o -name "*.conf")
mapfile -t config_board_files < <(find "${SRC}/config/boards" -type f -name "*.wip" -o -name "*.tvb" -o -name "*.conf" -o -name "*.csc" -o -name "*.eos")
# add all elements of config_source_files and config_board_files to config_files
config_files=("${config_source_files[@]}" "${config_board_files[@]}")

echo "Running shellcheck ${ACTUAL_VERSION} against ${#config_files[@]} config files, severity 'SEVERITY=${SEVERITY}', please wait..."
#echo "All params: " "${params[@]}"
#echo "Checked files: " "${config_files[@]}"

if "${SHELLCHECK_BIN}" "${params[@]}" "${config_files[@]}"; then
	echo "Congrats, no ${SEVERITY}'s detected in config/sources."
else
	echo "Ooops, ${SEVERITY}'s detected in config/sources."
	problems+=("Ooops, ${SEVERITY}'s detected in config/sources.")
fi

# Lib/ code checks
SEVERITY="critical"
declare -a params=()
calculate_params_for_severity
echo "Running shellcheck ${ACTUAL_VERSION} against 'compile.sh' -- lib/ checks, severity 'SEVERITY=${SEVERITY}', please wait..."
echo "All params: " "${params[@]}"

if "${SHELLCHECK_BIN}" "${params[@]}" compile.sh; then
	echo "Congrats, no ${SEVERITY}'s detected in lib/ code."
else
	problems+=("Ooops, ${SEVERITY}'s detected in lib/ code.")
fi

# show the problems, if any
if [[ ${#problems[@]} -gt 0 ]]; then
	echo "Problems detected:"
	for problem in "${problems[@]}"; do
		echo " - ${problem}"
	done
	exit 1
fi
