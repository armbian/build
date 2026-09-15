#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# The u-boot bare tree is a premade git tree pulled from an OCI artifact, the same way the Kernel
# one is. Unlike the Kernel there is no shallow/full decision to make: the artifact is ~390MiB,
# so one complete tree serves every board.
#
# The tree seeds mainline u-boot ('master' plus every tag -- most boards pin BOOTBRANCH to a
# 'tag:vYYYY.MM') and the Radxa vendor branches under 'radxa/*', which the rk35xx,
# rockchip-rk3588 and rockchip-rv1106 families build from. Every *other* u-boot fork Armbian
# builds fetches into this same tree; they are not seeded, but they land on top of mainline's
# history, so their fetches stay small.

# Sets outer scope: uboot_git_bare_tree, uboot_git_bundles_dir
function uboot_prepare_bare_repo() {
	# Path is unchanged from when this was a git clone; cli-patch.sh pushes from it by name.
	uboot_git_bare_tree="${SRC}/cache/git-bare/u-boot"      # outer scope
	uboot_git_bundles_dir="${SRC}/cache/git-bundles/u-boot" # outer scope

	# Deliberately not the Kernel's ".git/armbian-bare-tree-done". A tree carrying that older
	# marker was produced by the old `git clone` of mainline: it has no Radxa branches, plus an
	# origin remote, hooks and multiple packfiles. Accepting it would mean warm-cache users and
	# long-lived self-hosted runners silently never get the vendor branches, while fresh CI
	# runners do -- and it would not even save bandwidth, since the first rk35xx build on such a
	# tree fetches all of Radxa anyway. Treat the marker name as the artifact's version number.
	declare marker_rel=".git/armbian-bare-tree-done-oras"

	# Offline builds can't pull, and hard-failing a user who already has a working tree would be
	# a regression over the old behaviour. Accept either marker, and say what might be missing.
	if [[ "${OFFLINE_WORK}" == "yes" && -d "${uboot_git_bare_tree}" ]]; then
		if [[ -f "${uboot_git_bare_tree}/${marker_rel}" || -f "${uboot_git_bare_tree}/.git/armbian-bare-tree-done" ]]; then
			display_alert "OFFLINE_WORK: using the existing u-boot bare tree as-is" "vendor branches may be missing" "warn"
			git_ensure_safe_directory "${uboot_git_bare_tree}"
			return 0
		fi
	fi

	# GIT_ORAS_TARBALLS_SHALLOW_BASE_REF also drives the Kernel gitball; see kernel-git-oras.sh.
	declare base_oras_ref="${GIT_ORAS_TARBALLS_SHALLOW_BASE_REF:-"${GHCR_SOURCE}/armbian/shallow"}"

	# There is no shallow/full prompt for u-boot, so this alert is the only warning a first-time
	# user on a slow link gets before a few hundred MiB starts moving.
	display_alert "Preparing u-boot bare git tree" "~390 MiB download, first use only" "info"

	git_oras_tree_prepare_from_gitball \
		"u-boot" "${uboot_git_bare_tree}" "${marker_rel}" \
		"${base_oras_ref}/u-boot-git:latest" \
		"${uboot_git_bundles_dir}" "u-boot-complete.git.tar" \
		"${SRC}/cache/sources/u-boot-worktree"

	return 0
}

function uboot_cleanup_bundle_artifacts() {
	[[ -z "${uboot_git_bundles_dir}" ]] && exit_with_error "uboot_git_bundles_dir is not set"

	git_oras_tree_cleanup_bundles "u-boot" "${uboot_git_bundles_dir}"
}
