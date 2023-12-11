#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function uboot_main_patching_python() {
	prepare_python_and_pip

	# outer scope variable: uboot_work_dir

	temp_file_for_output="$(mktemp)" # Get a temporary file for the output.
	# array with all parameters; will be auto-quoted by bash's @Q modifier below
	declare -a params_quoted=(
		"${PYTHON3_VARS[@]}"                                  # Default vars, from prepare_python_and_pip
		"LOG_DEBUG=${SHOW_DEBUG}"                             # Logging level for python.
		"SRC=${SRC}"                                          # Armbian root
		"OUTPUT=${temp_file_for_output}"                      # Output file for the python script.
		"ASSET_LOG_BASE=$(print_current_asset_log_base_file)" # base file name for the asset log; to write .md summaries.
		"PATCH_TYPE=u-boot"                                   # or, u-boot, or, atf
		"PATCH_DIRS_TO_APPLY=${BOOTPATCHDIR}"                 # A space-separated list of directories to apply...
		"BOARD=${BOARD}"                                      # BOARD is needed for the patchset selection logic; mostly for u-boot.
		"TARGET=${target_patchdir}"                           # TARGET is need for u-boot's SPI/SATA etc selection logic
		"USERPATCHES_PATH=${USERPATCHES_PATH}"                # Needed to find the userpatches.
		# For table generation to fit into the screen, or being large when in GHA.
		"COLUMNS=${COLUMNS}"
		"GITHUB_ACTIONS=${GITHUB_ACTIONS}"
		# Needed so git can find the global .gitconfig, and Python can parse the PATH to determine which git to use.
		"PATH=${PATH}"
		"HOME=${HOME}"
		# What to do?
		"APPLY_PATCHES=yes"                      # Apply the patches to the filesystem. Does not imply git commiting. If no, still exports the hash.
		"PATCHES_TO_GIT=${PATCHES_TO_GIT:-no}"   # Commit to git after applying the patches.
		"REWRITE_PATCHES=${REWRITE_PATCHES:-no}" # Rewrite the original patch files after git commiting.
		# Git dir, revision, and target branch
		"GIT_WORK_DIR=${uboot_work_dir}"               # "Where to apply patches?"
		"BASE_GIT_REVISION=${uboot_git_revision}"      # The revision we're building/patching. Python will reset and clean to this.
		"BRANCH_FOR_PATCHES=u-boot-${BRANCH}-${BOARD}" # When applying patches-to-git, use this branch.
		# Lenience: allow problematic patches to be applied.
		"ALLOW_RECREATE_EXISTING_FILES=yes"       # Allow patches to recreate files that already exist.
		"GIT_ARCHEOLOGY=${GIT_ARCHEOLOGY:-no}"    # Allow git to do some archaeology to find the original patch's owners; used when patching to git/rewriting.
		"FAST_ARCHEOLOGY=${FAST_ARCHEOLOGY:-yes}" # Does archeology even further by looking for history from other patch files with the same name
		# Pass the maintainer info, used for commits.
		"MAINTAINER_NAME=${MAINTAINER}"      # Name of the maintainer
		"MAINTAINER_EMAIL=${MAINTAINERMAIL}" # Email of the maintainer
	)
	display_alert "Calling Python patching script" "for u-boot target" "info"

	# "raw_command" is only for logging purposes.
	raw_command="[...shortened u-boot patching...] ${PYTHON3_INFO[BIN]} ${SRC}/lib/tools/patching.py" \
		run_host_command_logged env -i "${params_quoted[@]@Q}" "${PYTHON3_INFO[BIN]}" "${SRC}/lib/tools/patching.py"
	run_host_command_logged cat "${temp_file_for_output}"
	# shellcheck disable=SC1090
	source "${temp_file_for_output}" # SOURCE IT!
	run_host_command_logged rm -f "${temp_file_for_output}"
	return 0
}
