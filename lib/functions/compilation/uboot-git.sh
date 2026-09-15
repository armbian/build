#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function uboot_prepare_git() {
	display_alert "Preparing git for u-boot" "BOOTSOURCE: ${BOOTSOURCE}" "debug"
	if [[ -n $BOOTSOURCE ]] && [[ "${BOOTSOURCE}" != "none" ]]; then
		# Prepare the git bare repo for u-boot; shared between all u-boot builds.
		declare uboot_git_bare_tree uboot_git_bundles_dir
		uboot_prepare_bare_repo # sets uboot_git_bare_tree and uboot_git_bundles_dir
		git_ensure_safe_directory "${uboot_git_bare_tree}"

		display_alert "Downloading sources" "u-boot; BOOTSOURCEDIR=${BOOTSOURCEDIR}" "git"

		# This var will be set by fetch_from_repo().
		declare checked_out_revision="undetermined"

		GIT_FIXED_WORKDIR="${BOOTSOURCEDIR}" \
			GIT_BARE_REPO_FOR_WORKTREE="${uboot_git_bare_tree}" \
			GIT_BARE_REPO_INITIAL_BRANCH="master" \
			GIT_SKIP_SUBMODULES="${UBOOT_GIT_SKIP_SUBMODULES}" \
			fetch_from_repo "$BOOTSOURCE" "$BOOTDIR" "$BOOTBRANCH" "yes" # fetch_from_repo <url> <dir> <ref> <subdir_flag>

		# Sets the outer scope variable
		uboot_git_revision="${checked_out_revision}"
		display_alert "Using u-boot revision SHA1" "${uboot_git_revision}"

		# fetch_from_repo() has now created a worktree off the extracted tree, resolved a
		# revision, checked it out and cleaned it -- so it has read real objects out of the
		# extracted pack and the downloaded tarball has served its purpose. The Kernel defers
		# this until after patching (compile_kernel), but u-boot has no single orchestrator:
		# uboot_prepare_git has two callers that patch in different places, and doing it here
		# covers both.
		uboot_cleanup_bundle_artifacts
	fi
	return 0
}
