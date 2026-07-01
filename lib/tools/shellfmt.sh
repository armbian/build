#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

SHELLFMT_VERSION=${SHELLFMT_VERSION:-3.13.1} # https://github.com/mvdan/sh/releases/

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
	curl -fLo "${SHELLFMT_BIN}" "${DOWN_URL}" || {
		echo "shellfmt download failed from ${DOWN_URL}"
		rm -f "${SHELLFMT_BIN}"
		exit 1
	}
	chmod +x "${SHELLFMT_BIN}"
fi

ACTUAL_VERSION="$("${SHELLFMT_BIN}" -version)"
echo "Running shellfmt ${ACTUAL_VERSION}"

# Resolve positional args to absolute paths BEFORE chdir, so callers
# from sub-directories can pass relative paths and have them keep
# meaning. Avoid `realpath -m` — its `-m` flag is GNU-only and breaks
# on the macOS realpath(1) the script's darwin branch otherwise
# supports. Plain `$PWD/path` prefix is enough; shfmt doesn't care
# about symlink canonicalisation or `..` normalisation, and the
# missing-file branch below still triggers on dangling paths.
declare -a SCOPED_ARGS=()
for _f in "$@"; do
	if [[ "${_f}" == /* ]]; then
		SCOPED_ARGS+=("${_f}")
	else
		SCOPED_ARGS+=("${PWD}/${_f}")
	fi
done

cd "${SRC}"
#"${SHELLFMT_BIN}" --help
#"${SHELLFMT_BIN}" -f "${SRC}"
#"${SHELLFMT_BIN}" -d "${SRC}"

# Should match the .editorconfig

# Allowed file extensions for both full-tree and scoped modes; keep
# in sync with the find globs below.
ALLOWED_EXT_RE='\.(sh|conf|inc|csc|tvb|eos|wip)$'

declare -a ALL_BASH_FILES=()

if ((${#SCOPED_ARGS[@]} > 0)); then
	# Scoped mode: only format the files passed on the command line.
	# Skip anything that doesn't match the allowed extensions so a
	# stray Python/Markdown/YAML argument doesn't sneak through.
	echo -e "\nScoped mode: formatting only the files passed on argv"
	for f in "${SCOPED_ARGS[@]}"; do
		if [[ ! -e "${f}" ]]; then
			echo "  skip (missing): ${f}"
			continue
		fi
		if [[ ! "${f}" =~ ${ALLOWED_EXT_RE} ]]; then
			echo "  skip (unsupported extension): ${f}"
			continue
		fi
		ALL_BASH_FILES+=("${f}")
	done
	if ((${#ALL_BASH_FILES[@]} == 0)); then
		echo "No eligible files after filtering — nothing to do."
		exit 0
	fi
else
	# Full-tree mode: aggregate every file the framework cares about.
	board_config_files=$(find config/boards -type f \( -name "*.conf" -o -name "*.csc" -o -name "*.tvb" -o -name "*.eos" -o -name "*.wip" \)) # All board config files
	family_config_files=$(find config/sources -type f \( -name "*.conf" -o -name "*.inc" -o -name "*.sh" \))                                  # All family config files
	lib_files=$(find lib -type f -name "*.sh")                                                                                                # All build framework shell files
	extensions_files=$(find extensions -type f -name "*.sh")                                                                                  # All extension shell files

	ALL_BASH_FILES=(compile.sh ${board_config_files} ${family_config_files} ${lib_files} ${extensions_files})
fi

echo -e "\nAll files:" "${ALL_BASH_FILES[@]}"

echo -e "\nShellfmt files differing:"
"${SHELLFMT_BIN}" -l "${ALL_BASH_FILES[@]}" | sort -h # list all formatted files

#echo "Diff with current:"
# "${SHELLFMT_BIN}" -d "${ALL_BASH_FILES[@]}" # list files that have different formatting than they should

echo -e "\nFormatting files..."
"${SHELLFMT_BIN}" -w "${ALL_BASH_FILES[@]}"

echo "Shellfmt finished!"
