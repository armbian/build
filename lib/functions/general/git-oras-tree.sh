#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Obtaining a premade git tree from an OCI artifact, shared by the Kernel and u-boot paths.
#
# The producer (https://github.com/armbian/shallow) builds a git tree, tars its .git directory,
# and pushes that tar to ghcr.io. Here we pull the tar and extract it into a "bare tree" -- which
# despite the name is a normal non-bare repo with an empty working copy; fetch_from_repo() hangs
# `git worktree`s off it. A marker file inside records that the extraction completed, so a
# half-finished download is never mistaken for a usable tree.
#
# Everything is passed in explicitly: the callers own wildly different config vars, and outer-scope
# coupling is what kept this from being reusable in the first place.

# <what> <tree_dir> <marker_rel> <oci_ref> <bundles_dir> <ball_fn> [<stale_worktrees_dir>]
#   what                human-readable subject for log lines, e.g. "Kernel" or "u-boot"
#   tree_dir            where the tree lives, e.g. ${SRC}/cache/git-bare/u-boot
#   marker_rel          done-marker, relative to tree_dir, e.g. ".git/armbian-bare-tree-done"
#   oci_ref             full OCI reference including the tag
#   bundles_dir         scratch directory for the download
#   ball_fn             file name inside the artifact, e.g. "u-boot-complete.git.tar"
#   stale_worktrees_dir optional; its *contents* are purged if the tree is (re-)extracted
#
# Idempotent, hard-fails via exit_with_error. Must run under a logging section; nothing here
# is interactive.
function git_oras_tree_prepare_from_gitball() {
	declare what="${1:?what is required}"
	declare tree_dir="${2:?tree_dir is required}"
	declare marker_rel="${3:?marker_rel is required}"
	declare oci_ref="${4:?oci_ref is required}"
	declare bundles_dir="${5:?bundles_dir is required}"
	declare ball_fn="${6:?ball_fn is required}"
	declare stale_worktrees_dir="${7:-""}"

	declare done_marker="${tree_dir}/${marker_rel}"

	if [[ ! -d "${tree_dir}" || ! -f "${done_marker}" ]]; then
		display_alert "Preparing bare ${what} git tree" "this might take a long time" "info"

		if [[ -d "${tree_dir}" ]]; then
			display_alert "Removing old ${what} bare tree" "${tree_dir}" "info"
			run_host_command_logged rm -rf "${tree_dir}"
		fi

		# Worktrees are registered on both ends: the worktree's .git file points into
		# ${tree_dir}/.git/worktrees/<name>, and fetch_from_repo() hard-fails (see
		# lib/functions/general/git.sh, "Bare repo worktree gitdir not found") when it finds a
		# worktree whose registry entry has gone. Replacing the tree orphans every one of them,
		# so they have to go with it. Contents only -- these directories are Docker mountpoints
		# and removing the directory itself is EBUSY inside the container.
		if [[ -n "${stale_worktrees_dir}" && -d "${stale_worktrees_dir}" ]]; then
			display_alert "Purging ${what} worktrees orphaned by bare tree removal" "${stale_worktrees_dir}" "warn"
			run_host_command_logged rm -rf "${stale_worktrees_dir:?}/"*
		fi

		wait_for_disk_sync "before ${what} git tree download"

		declare git_oras_tree_tar_file
		git_oras_tree_download_gitball "${what}" "${oci_ref}" "${bundles_dir}" "${ball_fn}" # sets git_oras_tree_tar_file or dies

		wait_for_disk_sync "before ${what} git extraction"

		# Just extract the tar_file into the "${tree_dir}" directory, no further work needed.
		run_host_command_logged mkdir -p "${tree_dir}"
		# @TODO chance of a pv thingy here?
		run_host_command_logged tar -xf "${git_oras_tree_tar_file}" -C "${tree_dir}"

		wait_for_disk_sync "after ${what} git extraction"

		# sanity check
		if [[ ! -d "${tree_dir}/.git" ]]; then
			exit_with_error "${what} bare tree is missing .git directory ${tree_dir}"
		fi

		# write the marker file
		touch "${done_marker}"
	else
		display_alert "${what} bare tree already exists" "${tree_dir}" "cachehit"
	fi

	git_ensure_safe_directory "${tree_dir}"

	return 0
}

# <what> <oci_ref> <bundles_dir> <ball_fn>
# Sets outer-scope 'git_oras_tree_tar_file' to the downloaded file, or dies trying.
function git_oras_tree_download_gitball() {
	declare what="${1:?what is required}"
	declare oci_ref="${2:?oci_ref is required}"
	declare bundles_dir="${3:?bundles_dir is required}"
	declare ball_fn="${4:?ball_fn is required}"

	run_host_command_logged mkdir -p "${bundles_dir}" # cleaned up later by git_oras_tree_cleanup_bundles()

	# defines outer scope value
	git_oras_tree_tar_file="${bundles_dir}/${ball_fn}"

	# if the file already exists, do nothing; it will only exist if successfully downloaded by ORAS
	if [[ -f "${git_oras_tree_tar_file}" ]]; then
		display_alert "${what} git-tarball already exists" "${ball_fn}" "cachehit"
		return 0
	fi

	# do_with_retries 5 xxx ? -- no -- oras_pull_artifact_file should do it's own retries.
	oras_pull_artifact_file "${oci_ref}" "${bundles_dir}" "${ball_fn}"

	# sanity check
	if [[ ! -f "${git_oras_tree_tar_file}" ]]; then
		exit_with_error "${what} git-tarball download failed ${git_oras_tree_tar_file}"
	fi

	return 0
}

# <what> <bundles_dir>
# Drop the downloaded tar once the extracted tree has proven itself; it is dead weight afterwards.
function git_oras_tree_cleanup_bundles() {
	declare what="${1:?what is required}"
	declare bundles_dir="${2:?bundles_dir is required}"

	if [[ -d "${bundles_dir}" ]]; then
		display_alert "Cleaning up ${what} git bundle artifacts" "no longer needed" "info"
		run_host_command_logged rm -rf "${bundles_dir}"
	fi

	return 0
}
