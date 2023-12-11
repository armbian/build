#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# advanced_patch <patch_kind> <{patch_dir}> <board> <target> <branch> <description>
#
# parameters:
# <patch_kind>: u-boot, kernel, atf
# <{patch_dir}>: u-boot: u-boot, u-boot-neo; kernel: sun4i-default, sunxi-next, ...
# <board>: cubieboard, cubieboard2, cubietruck, ...
# <target>: optional subdirectory
# <description>: additional description text

# calls:
#                         ${patch_kind}  ${patch_dir}      $board   $target            $branch   $description
# kernel: advanced_patch "kernel"       "$KERNELPATCHDIR" "$BOARD" ""                 "$BRANCH" "$LINUXFAMILY-$BRANCH"
# u-boot: advanced_patch "u-boot"       "$BOOTPATCHDIR"   "$BOARD" "$target_patchdir" "$BRANCH" "${LINUXFAMILY}-${BOARD}-${BRANCH}"
function advanced_patch() {
	local patch_kind="$1"
	local patch_dir="$2"
	local board="$3"
	local target="$4"
	local branch="$5"
	local description="$6"

	display_alert "Started patching process for" "${patch_kind} $description" "info"
	display_alert "Looking for user patches in" "userpatches/${patch_kind}/${patch_dir}" "info"

	local names=()
	local dirs=(
		"$USERPATCHES_PATH/${patch_kind}/${patch_dir}/target_${target}:[\e[33mu\e[0m][\e[34mt\e[0m]"
		"$USERPATCHES_PATH/${patch_kind}/${patch_dir}/board_${board}:[\e[33mu\e[0m][\e[35mb\e[0m]"
		"$USERPATCHES_PATH/${patch_kind}/${patch_dir}/branch_${branch}:[\e[33mu\e[0m][\e[33mb\e[0m]"
		"$USERPATCHES_PATH/${patch_kind}/${patch_dir}:[\e[33mu\e[0m][\e[32mc\e[0m]"

		"$SRC/patch/${patch_kind}/${patch_dir}/target_${target}:[\e[32ml\e[0m][\e[34mt\e[0m]" # used for u-boot "spi" stuff
		"$SRC/patch/${patch_kind}/${patch_dir}/board_${board}:[\e[32ml\e[0m][\e[35mb\e[0m]"   # used for u-boot board-specific stuff
		"$SRC/patch/${patch_kind}/${patch_dir}/branch_${branch}:[\e[32ml\e[0m][\e[33mb\e[0m]" # NOT used, I think.
		"$SRC/patch/${patch_kind}/${patch_dir}:[\e[32ml\e[0m][\e[32mc\e[0m]"                  # used for everything
	)
	local links=()

	# required for "for" command
	# @TODO these shopts leak for the rest of the build script! either make global, or restore them after this function
	shopt -s nullglob dotglob
	# get patch file names
	for dir in "${dirs[@]}"; do
		for patch in ${dir%%:*}/*.patch; do
			names+=($(basename "${patch}"))
		done
		# add linked patch directories
		if [[ -d ${dir%%:*} ]]; then
			local findlinks
			findlinks=$(find "${dir%%:*}" -maxdepth 1 -type l -print0 2>&1 | xargs -0)
			[[ -n $findlinks ]] && readarray -d '' links < <(find "${findlinks}" -maxdepth 1 -type f -follow -print -iname "*.patch" -print | grep "\.patch$" | sed "s|${dir%%:*}/||g" 2>&1)
		fi
	done

	# merge static and linked
	names=("${names[@]}" "${links[@]}")
	# remove duplicates
	local names_s=($(echo "${names[@]}" | tr ' ' '\n' | LC_ALL=C sort -u | tr '\n' ' '))
	# apply patches
	for name in "${names_s[@]}"; do
		for dir in "${dirs[@]}"; do
			if [[ -f ${dir%%:*}/$name ]]; then
				if [[ -s ${dir%%:*}/$name ]]; then
					process_patch_file "${dir%%:*}/$name" "${dir##*:}"
				else
					display_alert "* ${dir##*:} $name" "skipped"
				fi
				break # next name
			fi
		done
	done
}

# process_patch_file <file> <description>
#
# parameters:
# <file>: path to patch file
# <status>: additional status text
#
process_patch_file() {
	local patch="${1}"
	local status="${2}"
	local -i patch_date
	local relative_patch="${patch##"${SRC}"/}" # ${FOO##prefix} remove prefix from FOO

	# detect and remove files which patch will create
	lsdiff -s --strip=1 "${patch}" | grep '^+' | awk '{print $2}' | xargs -I % sh -c 'rm -f %'

	# shellcheck disable=SC2015 # noted, thanks. I need to handle exit code here.
	patch --batch -p1 -N --input="${patch}" --quiet --reject-file=- && { # "-" discards rejects
		display_alert "* $status ${relative_patch}" "" "info"
	} || {
		display_alert "* $status ${relative_patch}" "failed" "err"
		exit_with_error "Patching error, exiting."
	}

	return 0 # short-circuit above, avoid exiting with error
}

function userpatch_create() {
	declare patch_type="${1}"

	declare -a common_git_params=(
		"-c" "commit.gpgsign=false"
		"-c" "user.name='${MAINTAINER}'"
		"-c" "user.email='${MAINTAINERMAIL}'"
	)

	# export the commit as a patch
	declare formatpatch_params=(
		"-1" "HEAD" "--stdout"
		"--unified=5"    # force 5 lines of diff context
		"--keep-subject" # do not add a prefix to the subject "[PATCH] "
		'--signature' "'Created with Armbian build tools https://github.com/armbian/build'"
		'--stat=120'            # 'wider' stat output; default is 80
		'--stat-graph-width=10' # shorten the diffgraph graph part, it's too long
		"--zero-commit"         # Output an all-zero hash in each patch’s From header instead of the hash of the commit.
	)

	# if stdin is not a terminal, bail out
	[[ -t 0 ]] || exit_with_error "patching: stdin is not a terminal"
	[[ -t 1 ]] || exit_with_error "patching: stdout is not a terminal"

	# Display a header with instructions about MAINTAINER and MAINTAINERMAIL
	display_alert "Starting" "interactive patching process for ${patch_type}" "ext"

	# create commit to start from clean source; don't fail.
	display_alert "Creating commit to start from clean source" "" "info"
	run_host_command_logged git "${common_git_params[@]}" add . "||" true
	run_host_command_logged git "${common_git_params[@]}" commit -q -m "'Previous changes made by Armbian'" "||" true

	display_alert "Patches will be created" "with the following maintainer information" "info"
	display_alert "MAINTAINER (Real name): " "${MAINTAINER}" "info"
	display_alert "MAINTAINERMAIL (Email): " "${MAINTAINERMAIL}" "info"
	display_alert "If those are not correct, set them in your environment, command line, or config file and restart the process" "" ""

	mkdir -p "${DEST}/patch"
	declare patch="${DEST}/patch/${patch_type}-${LINUXFAMILY}-${BRANCH}.patch"

	# prompt to alter source
	display_alert "Make your changes in this directory:" "$(pwd)" "wrn"
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then
		display_alert "You are running in a container" "Path shown above might not match host system, be aware." "wrn"
	fi

	# If the ${patch} file already exists, offer to apply it before continuing patching.
	if [[ -f "${patch}" ]]; then
		display_alert "A previously-created patch file already exists!" "${patch}" "wrn"
		declare apply_patch
		read -r -e -p "Do you want to apply it before continuing? [y/N] " apply_patch
		if [[ "${apply_patch}" == "y" ]]; then
			display_alert "Applying patch" "${patch}" "info"
			run_host_command_logged git "${common_git_params[@]}" apply "${patch}" || display_alert "Patch failed to apply, continuing..." "${patch}" "wrn"
		fi
	fi

	# Enter a loop, waiting for ENTER, then showing the git diff, and have the user confirm he is happy with patch
	declare user_happy="no"
	while [[ "${user_happy}" != "yes" ]]; do
		display_alert "Press <ENTER> after you are done" "editing files in $(pwd)" "wrn"
		# Wait for user to press ENTER
		declare stop_patching
		read -r -e -p "Press ENTER to show a preview of your patch, or type 'stop' to stop patching..." stop_patching
		[[ "${stop_patching}" == "stop" ]] && exit_with_error "Aborting due to" "user request"

		# Detect if there are any changes done to the working tree
		declare -i changes_in_working_tree
		changes_in_working_tree=$(git "${common_git_params[@]}" status --porcelain | wc -l)
		if [[ ${changes_in_working_tree} -lt 1 ]]; then
			display_alert "No changes detected!" "No changes in the working tree, please edit files and try again" "wrn"
			continue # no changes, loop again
		fi

		display_alert "OK, here's how your diff looks like" "showing patch diff" "info"
		git "${common_git_params[@]}" diff | run_tool_batcat --file-name "${patch}" -

		# Prompt the user if he is happy with the patch
		display_alert "Are you happy with this patch?" "Type 'yes' to accept, 'stop' to stop patching, or anything else to keep patching" "wrn"

		# Wait for user to type yes or no
		read -r -e -p "Are you happy with the diff above? Type 'y' or 'yes' to accept, 'stop' to stop patching, anything else to keep patching: " -i "" user_happy

		declare first_uppercase_character_of_user_happy="${user_happy:0:1}"
		first_uppercase_character_of_user_happy="${first_uppercase_character_of_user_happy^^}"
		[[ "${first_uppercase_character_of_user_happy}" == "Y" ]] && break

		[[ "${first_uppercase_character_of_user_happy}" == "S" ]] && exit_with_error "Aborting due to user request"

		display_alert "Not happy? No problem!" "just keep on editing the files..." "wrn"
	done

	display_alert "OK, user is happy with diff" "proceeding with patch creation" "ext"

	run_host_command_logged git add .

	# create patch out of changes
	if ! git "${common_git_params[@]}" diff-index --quiet --cached HEAD; then

		# Default the patch_commit_message.
		# Get a list of all the filenames in the git diff into a bash array...
		declare -a changed_filenames=($(git "${common_git_params[@]}" diff-index --cached --name-only HEAD))
		display_alert "Names of the changed files" "${changed_filenames[*]@Q}" "info"
		declare patch_commit_message="Patching ${patch_type} ${LINUXFAMILY} files ${changed_filenames[*]@Q}"

		# If Git is configured, create proper patch and ask for a name
		display_alert "Add / change patch name" "${patch_commit_message}" "wrn"
		read -e -p "Patch Subject: " -i "${patch_commit_message}" patch_commit_message
		[[ -z "${patch_commit_message}" ]] && patch_commit_message="Patching something unknown and mysterious"
		run_host_command_logged git "${common_git_params[@]}" commit -s -m "'${patch_commit_message}'"
		run_host_command_logged git "${common_git_params[@]}" format-patch "${formatpatch_params[@]}" ">" "${patch}"

		display_alert "You will find your patch here:" "${patch}" "info"
		run_tool_batcat --file-name "${patch}" "${patch}"
		display_alert "You will find your patch here:" "${patch}" "info"
		display_alert "Now you can manually move the produced patch to your userpatches or core patches to have it included in the next build" "${patch}" "ext"
	else
		display_alert "No changes found, skipping patch creation" "" "err"
	fi
}
