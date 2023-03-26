#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# defines the format for KERNELBRANCH, BOOTBRANCH, and arguments to fetch_from_repo.
# branch:xxx, tag:yyyy, commit:zzzz, head.
# sets: ref_type=branch|tag|commit, ref_name=xxx|yyyy|zzzz|HEAD
function git_parse_ref() {
	declare ref="$1"
	[[ -z $ref || ($ref != tag:* && $ref != branch:* && $ref != head && $ref != commit:*) ]] && exit_with_error "Error in configuration; git_ref '${ref}' is not valid"
	ref_type=${ref%%:*} # outer scope
	ref_name=${ref##*:} # outer scope
	if [[ $ref_type == head ]]; then
		ref_name=HEAD
	fi
}

#
# This function retries Git operations to avoid failure in case remote is borked
#
function improved_git() {
	local real_git
	real_git="$(command -v git)"
	local retries=3
	local delay=10
	local count=0
	while [ $count -lt $retries ]; do
		run_host_command_logged_raw "$real_git" --no-pager "$@" && return 0 # this gobbles up errors, but returns if OK, so everything after is error
		count=$((count + 1))
		display_alert "improved_git try $count failed, retrying in ${delay} seconds" "git $*" "warn"
		sleep $delay
	done
	display_alert "improved_git, too many retries" "git $*" "err"
	return 17 # explode with error if this is reached, "too many retries"
}

# Not improved, just regular, but logged "correctly".
function regular_git() {
	run_host_command_logged_raw git --no-pager "$@"
}

# avoid repeating myself too much
function improved_git_fetch() {
	declare -a verbose_params=() && if_user_on_terminal_and_not_logging_add verbose_params "--verbose" "--progress"
	# --no-auto-maintenance requires a recent git version, not available on focal-like host OSs
	improved_git fetch "${verbose_params[@]}" --recurse-submodules=no "$@"
}

# workaround new limitations imposed by CVE-2022-24765 fix in git, otherwise  "fatal: unsafe repository"
function git_ensure_safe_directory() {
	if [[ -n "$(command -v git)" ]]; then
		local git_dir="$1"
		display_alert "git: Marking all directories as safe, which should include" "$git_dir" "debug"
		if ! grep -q "directory = \*" "${HOME}/.gitconfig" 2> /dev/null; then
			git config --global --add safe.directory "*"
		fi
	else
		display_alert "git not installed" "a true wonder how you got this far without git - it will be installed for you" "warn"
	fi
}

# fetch_from_repo <url> <directory> <ref> <ref_subdir>
# <url>: remote repository URL
# <directory>: local directory; subdir for branch/tag will be created
# <ref>:
#	branch:name
#	tag:name
#	head(*)
#	commit:hash
#
# *: Implies ref_subdir=no
#
# <ref_subdir>: "yes" to create subdirectory for tag or branch name
#
function fetch_from_repo() {
	display_alert "fetch_from_repo" "$*" "git"
	local url=$1
	local dir=$2
	local ref=$3
	local ref_subdir=$4
	local git_work_dir

	# Set GitHub mirror before anything else touches $url
	url=${url//'https://github.com/'/$GITHUB_SOURCE'/'}

	# The 'offline' variable must always be set to 'true' or 'false'
	local offline=false
	if [[ "${OFFLINE_WORK}" == "yes" ]]; then
		offline=true
	fi

	declare ref_type ref_name
	git_parse_ref "$ref"

	display_alert "Getting sources from Git" "$dir $ref_name" "info"

	local workdir=$dir
	if [[ $ref_subdir == yes ]]; then
		workdir=$dir/$ref_name
	fi

	git_work_dir="${SRC}/cache/sources/${workdir}"

	# if GIT_FIXED_WORKDIR has something, ignore above logic and use that directly.
	if [[ "${GIT_FIXED_WORKDIR}" != "" ]]; then
		display_alert "GIT_FIXED_WORKDIR is set to" "${GIT_FIXED_WORKDIR}" "git"
		git_work_dir="${SRC}/cache/sources/${GIT_FIXED_WORKDIR}"
	fi

	display_alert "Git working dir" "${git_work_dir}" "git"

	# Support using worktrees; needs GIT_BARE_REPO_FOR_WORKTREE set
	if [[ "x${GIT_BARE_REPO_FOR_WORKTREE}x" != "xx" ]]; then
		# If it is already a worktree...
		if [[ -f "${git_work_dir}/.git" ]]; then
			display_alert "Using existing worktree" "${git_work_dir}" "git"
		else
			if [[ -d "${git_work_dir}" ]]; then
				display_alert "Removing previously half-checked-out tree" "${git_work_dir}" "warn"
				cd "${SRC}" || exit_with_error "Could not cd to ${SRC}"
				rm -rf "${git_work_dir}"
			fi
			display_alert "Creating new worktree" "${git_work_dir}" "git"
			run_host_command_logged git -C "${GIT_BARE_REPO_FOR_WORKTREE}" worktree add "${git_work_dir}" "${GIT_BARE_REPO_INITIAL_BRANCH}" --no-checkout --force
			cd "${git_work_dir}" || exit
		fi
		cd "${git_work_dir}" || exit

		# Fix the reference to the bare repo; this avoids errors when the bare repo is moved.
		display_alert "Original gitdir: " "$(cat "${git_work_dir}/.git")" "git"
		local git_work_dir_basename
		git_work_dir_basename="$(basename "${git_work_dir}")"
		echo "gitdir: $(realpath --relative-to=${git_work_dir} ${GIT_BARE_REPO_FOR_WORKTREE}/.git/worktrees/${git_work_dir_basename})" > "${git_work_dir}/.git"
		display_alert "Modified gitdir: " "$(cat "${git_work_dir}/.git")" "git"

		# Fix the bare repo's reference to the working tree; this avoids errors when the working tree is moved.
		local bare_repo_wt_path="${GIT_BARE_REPO_FOR_WORKTREE}/.git/worktrees/${git_work_dir_basename}"
		local bare_repo_wt_gitdir="${bare_repo_wt_path}/gitdir"
		if [[ -f "${bare_repo_wt_gitdir}" ]]; then
			display_alert "Original bare repo gitdir: " "$(cat "${bare_repo_wt_gitdir}")" "git"
			run_host_command_logged echo "${git_work_dir}/.git" ">" "${bare_repo_wt_gitdir}"
			display_alert "Modified bare repo gitdir: " "$(cat "${bare_repo_wt_gitdir}")" "git"
		else
			display_alert "No bare repo worktree gitdir found" "${bare_repo_wt_gitdir}" "err"
			display_alert "Did you shuffle worktrees around?" "Don't shuffle worktrees around" "err"
			display_alert "Did you shuffle bare trees around?" "Don't shuffle bare trees around" "err"
			display_alert "Did you NOT do anything of the sort?" "Open a bug report / reset your cache." "err"
			exit_with_error "Bare repo worktree gitdir not found: ${bare_repo_wt_gitdir}"
		fi
		git_ensure_safe_directory "${git_work_dir}"
	else
		mkdir -p "${git_work_dir}" || exit_with_error "No path or no write permission" "${git_work_dir}"
		cd "${git_work_dir}" || exit
		git_ensure_safe_directory "${git_work_dir}"

		if [[ ! -d ".git" || "$(git rev-parse --git-dir)" != ".git" ]]; then
			# Dir is not a git working copy. Make it so;
			display_alert "Initializing empty git local copy" "git init: $dir $ref_name"
			regular_git init -q . # --initial-branch="armbian_unused_initial_branch" is not supported under focal
			offline=false         # Force online, we'll need to fetch.
		fi
	fi

	local changed=false

	# get local hash; might fail
	local local_hash
	local_hash=$(git rev-parse @ 2> /dev/null || true) # Don't fail nor output anything if failure

	# remote hash; will be calculated depending on ref_type below
	local remote_hash

	# when we work offline we simply return the sources to their original state
	if ! $offline; then

		case $ref_type in
			branch)
				# TODO: grep refs/heads/$name
				remote_hash=$(git ls-remote -h "${url}" "$ref_name" | head -1 | cut -f1)
				[[ -z $local_hash || "${local_hash}" != "a${remote_hash}" ]] && changed=true
				;;
			tag)
				remote_hash=$(git ls-remote -t "${url}" "$ref_name" | cut -f1)
				if [[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]]; then
					remote_hash=$(git ls-remote -t "${url}" "$ref_name^{}" | cut -f1)
					[[ -z $remote_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
				fi
				;;
			head)
				remote_hash=$(git ls-remote "${url}" HEAD | cut -f1)
				[[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
				;;
			commit)
				remote_hash="${ref_name}"
				[[ -z $local_hash || $local_hash == "@" || "${local_hash}" != "${remote_hash}" ]] && changed=true
				;;
		esac

		display_alert "Git local_hash vs remote_hash" "${local_hash} vs ${remote_hash}" "git"

	fi # offline

	local checkout_from="HEAD" # Probably best to use the local revision?

	if [[ "${changed}" == "true" ]]; then

		# remote was updated, fetch and check out updates, but not tags; tags pull their respective commits too, making it a huge fetch.
		display_alert "Fetching updates from remote repository" "$dir $ref_name"
		case $ref_type in
			branch)
				improved_git_fetch --no-tags "${url}" "${ref_name}"
				;;
			tag)
				improved_git_fetch --no-tags "${url}" tags/"${ref_name}"
				;;
			head)
				improved_git_fetch --no-tags "${url}" HEAD
				;;
			commit)
				# @TODO: if the local copy has the revision, skip the fetch -- would save us a lot of time
				display_alert "Fetching a specific commit/sha1" "${ref_name}" "debug"
				improved_git_fetch --no-tags "${url}" "${ref_name}"
				;;
		esac

		checkout_from="FETCH_HEAD"
	fi

	# if the tree is shallow and big, this first rev-parse takes a while; use info to inform about what is done
	display_alert "git: Fetch from remote completed, rev-parsing..." "'$dir' '$ref_name' '${checkout_from}'" "info"

	# should be declared in outer scope: fetched_revision fetched_revision_ts
	fetched_revision="$(git rev-parse "${checkout_from}")"
	fetched_revision_ts="$(git log -1 --pretty=%ct "${checkout_from}")" # unix timestamp of the commit date
	display_alert "Fetched revision: fetched_revision:" "${fetched_revision}" "git"
	display_alert "Fetched revision: fetched_revision_ts:" "${fetched_revision_ts}" "git"

	if [[ "${do_checkout:-"yes"}" == "yes" ]]; then
		display_alert "git checking out revision SHA" "${fetched_revision}" "git"
		regular_git checkout -f -q "${fetched_revision}" # Return the files that are tracked by git to the initial state.

		# should be declared in outer scope: checked_out_revision checked_out_revision_ts
		checked_out_revision="${fetched_revision}"
		checked_out_revision_ts="${fetched_revision_ts}"
		display_alert "Fetched revision: checked_out_revision:" "${checked_out_revision}" "git"
		display_alert "Fetched revision: checked_out_revision_ts:" "${checked_out_revision_ts}" "git"

		display_alert "git cleaning" "${checked_out_revision}" "git"
		regular_git clean -q -d -f # Removes files that are not tracked by git. Does not remove .gitignore'd files.

		if [[ -f .gitmodules ]]; then
			if [[ "${GIT_SKIP_SUBMODULES}" == "yes" ]]; then
				display_alert "Skipping submodules" "GIT_SKIP_SUBMODULES=yes" "debug"
			else
				display_alert "Updating submodules" "" "ext"
				# FML: http://stackoverflow.com/a/17692710
				for i in $(git config -f .gitmodules --get-regexp path | awk '{ print $2 }'); do
					cd "${git_work_dir}" || exit
					local surl sref
					surl=$(git config -f .gitmodules --get "submodule.$i.url")
					sref=$(git config -f .gitmodules --get "submodule.$i.branch" || true)
					if [[ -n $sref ]]; then
						sref="branch:$sref"
					else
						sref="head"
					fi
					display_alert "Updating submodule" "$i - $surl - $sref" "git"
					git_ensure_safe_directory "$workdir/$i"
					fetch_from_repo "$surl" "$workdir/$i" "$sref"
				done
			fi
		fi
	else
		display_alert "Skipping checkout" "$dir $ref_name ${checked_out_revision}" "info"
	fi

	return 0
}
