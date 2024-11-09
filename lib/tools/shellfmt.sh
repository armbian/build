#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

SHELLFMT_VERSION=${SHELLFMT_VERSION:-3.10.0} # https://github.com/mvdan/sh/releases/

SRC="$(
	cd "$(dirname "$0")/../.."
	pwd -P
)"
echo "SRC: ${SRC}"

DIR_SHELLFMT="${SRC}/cache/tools/shellfmt"
mkdir -p "${DIR_SHELLFMT}"

MACHINE="${BASH_VERSINFO[5]}"
case "$MACHINE" in
	*darwin*) SHELLFMT_OS="darwin" ;;
	*linux*) SHELLFMT_OS="linux" ;;
	*)
		echo "unknown os: $MACHINE"
		exit 3
		;;
esac

case "$MACHINE" in
	*aarch64*) SHELLFMT_ARCH="arm64" ;;
	*x86_64*) SHELLFMT_ARCH="amd64" ;;
	*)
		echo "unknown arch: $MACHINE"
		exit 2
		;;
esac

SHELLFMT_FN="shfmt_v${SHELLFMT_VERSION}_${SHELLFMT_OS}_${SHELLFMT_ARCH}"
DOWN_URL="${GITHUB_SOURCE:-"https://github.com"}/mvdan/sh/releases/download/v${SHELLFMT_VERSION}/${SHELLFMT_FN}"
SHELLFMT_BIN="${DIR_SHELLFMT}/${SHELLFMT_FN}"

echo "MACHINE: ${MACHINE}"
echo "Download URL: ${DOWN_URL}"
echo "SHELLFMT_BIN: ${SHELLFMT_BIN}"

if [[ ! -f "${SHELLFMT_BIN}" ]]; then
	echo "Cache miss, downloading..."
	wget -O "${SHELLFMT_BIN}" "${DOWN_URL}"
	chmod +x "${SHELLFMT_BIN}"
fi

ACTUAL_VERSION="$("${SHELLFMT_BIN}" -version)"
echo "Running shellfmt ${ACTUAL_VERSION}"

cd "${SRC}"
#"${SHELLFMT_BIN}" --help
#"${SHELLFMT_BIN}" -f "${SRC}"
#"${SHELLFMT_BIN}" -d "${SRC}"

# Should match the .editorconfig

# Aggregate all files that should be formatted
board_config_files=$(find config/boards -type f \( -name "*.conf" -o -name "*.csc" -o -name "*.tvb" \))  # All board config files
family_config_files=$(find config/sources -type f \( -name "*.conf" -o -name "*.inc" -o -name "*.sh" \)) # All family config files
lib_files=$(find lib -type f -name "*.sh")                                                               # All build framework shell files
extensions_files=$(find extensions -type f -name "*.sh")                                                 # All extension shell files

declare -a ALL_BASH_FILES=(compile.sh ${board_config_files} ${family_config_files} ${lib_files} ${extensions_files})

echo -e "\nAll files:" "${ALL_BASH_FILES[@]}"

echo -e "\nShellfmt files differing:"
"${SHELLFMT_BIN}" -l "${ALL_BASH_FILES[@]}" | sort -h # list all formatted files

#echo "Diff with current:"
# "${SHELLFMT_BIN}" -d "${ALL_BASH_FILES[@]}" # list files that have different formatting than they should

echo -e "\nFormatting files..."
"${SHELLFMT_BIN}" -w "${ALL_BASH_FILES[@]}"

echo "Shellfmt finished!"
