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
		display_alert "* $status ${relative_patch}" "failed" "wrn"
		[[ $EXIT_PATCHING_ERROR == yes ]] && exit_with_error "Aborting due to" "EXIT_PATCHING_ERROR"
	}

	return 0 # short-circuit above, avoid exiting with error
}

userpatch_create() {
	display_alert "@TODO" "@TODO armbian-next" "warn"
	# create commit to start from clean source
	git add .
	git -c user.name='Armbian User' -c user.email='user@example.org' commit -q -m "Cleaning working copy"

	mkdir -p "${DEST}/patch"
	local patch="$DEST/patch/$1-$LINUXFAMILY-$BRANCH.patch"

	# apply previous user debug mode created patches
	if [[ -f $patch ]]; then
		display_alert "Applying existing $1 patch" "$patch" "wrn" && patch --batch --silent -p1 -N < "${patch}"
		# read title of a patch in case Git is configured
		if [[ -n $(git config user.email) ]]; then
			COMMIT_MESSAGE=$(cat "${patch}" | grep Subject | sed -n -e '0,/PATCH/s/.*PATCH]//p' | xargs)
			display_alert "Patch name extracted" "$COMMIT_MESSAGE" "wrn"
		fi
	fi

	# prompt to alter source
	display_alert "Make your changes in this directory:" "$(pwd)" "wrn"
	display_alert "Press <Enter> after you are done" "waiting" "wrn"
	read -r < /dev/tty
	tput cuu1
	git add .
	# create patch out of changes
	if ! git diff-index --quiet --cached HEAD; then
		# If Git is configured, create proper patch and ask for a name
		if [[ -n $(git config user.email) ]]; then
			display_alert "Add / change patch name" "$COMMIT_MESSAGE" "wrn"
			read -e -p "Patch description: " -i "$COMMIT_MESSAGE" COMMIT_MESSAGE
			[[ -z "$COMMIT_MESSAGE" ]] && COMMIT_MESSAGE="Patching something"
			git commit -s -m "$COMMIT_MESSAGE"
			git format-patch -1 HEAD --stdout --signature="Created with Armbian build tools https://github.com/armbian/build" > "${patch}"
			PATCHFILE=$(git format-patch -1 HEAD)
			rm $PATCHFILE # delete the actual file
			# create a symlink to have a nice name ready
			find $DEST/patch/ -type l -delete # delete any existing
			ln -sf $patch $DEST/patch/$PATCHFILE
		else
			git diff --staged > "${patch}"
		fi
		display_alert "You will find your patch here:" "$patch" "info"
	else
		display_alert "No changes found, skipping patch creation" "" "wrn"
	fi
	git reset --soft HEAD~
	for i in {3..1..1}; do echo -n "$i." && sleep 1; done
}
