#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function cli_patch_kernel_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.
	declare -g DOCKER_PASS_SSH_AGENT="yes"              # Pass SSH agent to docker
	declare -g DOCKER_PASS_GIT="yes"                    # mount .git dir to docker; for archeology

	# inside-function-function: a dynamic hook, only triggered if this CLI runs.
	# install openssh-client, we'll need it to push the patched tree.
	function add_host_dependencies__ssh_client_for_patch_pushing_over_ssh() {
		declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} openssh-client"
	}

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

# Used by both kernel and u-boot patchers, to fool the config & init it
function common_config_for_automated_patching() {
	declare -g SYNC_CLOCK=no                 # don't waste time syncing the clock
	declare -g PATCHES_TO_GIT=yes            # commit to git.
	declare -g PATCH_ONLY=yes                # stop after patching.
	declare -g GIT_ARCHEOLOGY=yes            # do archeology
	declare -g FAST_ARCHEOLOGY=yes           # do archeology, but only for the exact path we need.
	declare -g KERNEL_CONFIGURE=no           # no menuconfig
	declare -g RELEASE="${RELEASE:-"jammy"}" # or whatever, not relevant, just fool the configuration
	declare -g BUILD_DESKTOP="no"            # config would ask for this otherwise, just fool the configuration

	# initialize the config # @TODO: rpardini: switch this to prep_conf_main_minimal_ni()
	prep_conf_main_build_single
}

function cli_patch_kernel_run() {
	display_alert "Patching kernel" "$BRANCH - rewrite: ${REWRITE_PATCHES:-"no"} " "info"

	common_config_for_automated_patching # prepare the config

	# <prepare the git sha1>
	declare -A GIT_INFO_KERNEL=([GIT_SOURCE]="${KERNELSOURCE}" [GIT_REF]="${KERNELBRANCH}")
	obtain_kernel_git_info_and_makefile # this populates GIT_INFO_KERNEL and sets KERNEL_GIT_SHA1 readonly global
	# </prepare the git sha1>

	# prepare push details, if set
	declare target_repo_url target_branch do_push="no"
	declare -a push_command=()
	determine_git_push_details "${LINUXFAMILY}-${KERNEL_MAJOR_MINOR}" # fills in the above; parameter is the branch name

	# Prepare the host and build kernel; without using standard build
	prepare_host   # This handles its own logging sections, and is possibly interactive.
	compile_kernel # This handles its own logging sections.

	display_alert "Done patching kernel" "${BRANCH} - ${LINUXFAMILY} - ${KERNEL_MAJOR_MINOR}" "cachehit"

	if [[ "${do_push}" == "yes" ]]; then
		display_alert "Pushing kernel to Git branch ${target_branch}" "${target_repo_url}" "info"
		git_ensure_safe_directory "${SRC}/cache/git-bare/kernel"
		push_command=(git -C "${SRC}/cache/git-bare/kernel" push "--force" "--verbose" "${target_repo_url}" "kernel-${LINUXFAMILY}-${KERNEL_MAJOR_MINOR}:${target_branch}")
		display_alert "Git push command: " "${push_command[*]}" "info"
		execute_git_push
	fi

	return 0

}

## Similar stuff as kernel, but for u-boot.
function cli_patch_uboot_pre_run() {
	cli_patch_kernel_pre_run # same as kernel
}

# For the u-boot version, we skip over building proper and instead just config/prepare/git/patch
# @TODO: if ATF and CRUST ever move to the Py patcher they'd also need to be done here for full rewriting glory
function cli_patch_uboot_run() {
	display_alert "Patching u-boot" "$BRANCH - rewrite: ${REWRITE_PATCHES:-"no"} " "info"

	common_config_for_automated_patching # prepare the config

	# <prepare the git sha1>
	declare -A GIT_INFO_UBOOT=([GIT_SOURCE]="${BOOTSOURCE}" [GIT_REF]="${BOOTBRANCH}")
	run_memoized GIT_INFO_UBOOT "git2info" memoized_git_ref_to_info "include_makefile_body"
	[[ "${GIT_INFO_UBOOT[SHA1]}" =~ ^[0-9a-f]{40}$ ]] || exit_with_error "SHA1 is not sane: '${GIT_INFO_UBOOT[SHA1]}'"
	# </prepare the git sha1>

	# prepare push details, if set
	declare target_repo_url target_branch do_push="no"
	declare -a push_command=()
	determine_git_push_details "${BOARD}-${BRANCH}" # fills in the above; parameter is the branch name

	# Prepare the host
	prepare_host # This handles its own logging sections, and is possibly interactive.

	# Prepare git...
	declare uboot_git_revision="not_determined_yet"
	LOG_SECTION="uboot_prepare_git" do_with_logging_unless_user_terminal uboot_prepare_git

	# change dir to u-boot checkout, since patch_uboot_target expects to be run there
	local ubootdir="${SRC}/cache/sources/${BOOTSOURCEDIR}"
	cd "${ubootdir}" || exit_with_error "Could not cd to ${ubootdir}"

	# do the patching
	LOG_SECTION="patch_uboot_target" do_with_logging patch_uboot_target

	display_alert "Done patching u-boot" "${BRANCH} - ${LINUXFAMILY} - ${BOOTSOURCE}#${BOOTBRANCH}" "cachehit"

	if [[ "${do_push}" == "yes" ]]; then
		display_alert "Pushing u-boot to Git branch ${target_branch}" "${target_repo_url}" "info"
		git_ensure_safe_directory "${SRC}/cache/git-bare/u-boot"
		push_command=(git -C "${SRC}/cache/git-bare/u-boot" push "--force" "--verbose" "${target_repo_url}" "u-boot-${BRANCH}-${BOARD}:${target_branch}")
		display_alert "Git push command: " "${push_command[*]}" "info"
		execute_git_push
	fi

}

function determine_git_push_details() {
	if [[ -n "${PUSH_TO_GITHUB}" ]]; then
		PUSH_TO_REPO="git@github.com:${PUSH_TO_GITHUB}.git"
		display_alert "Will push to GitHub" "${PUSH_TO_REPO}" "info"
	fi

	if [[ -n "${PUSH_TO_REPO}" ]]; then
		do_push="yes"
		declare ymd vendor_lc
		ymd="$(date +%Y%m%d)"
		vendor_lc="$(tr '[:upper:]' '[:lower:]' <<< "${VENDOR}" | tr ' ' '_')" # lowercase ${VENDOR} and replace spaces with underscores
		target_branch="${vendor_lc}-${1}-${ymd}${PUSH_BRANCH_POSTFIX:-""}"
		target_repo_url="${PUSH_TO_REPO}"
		display_alert "Will push to Git" "${target_repo_url} branch ${target_branch}" "info"
	else
		display_alert "Will NOT push to Git" "use PUSH_TO_GITHUB=org/repo or PUSH_TO_REPO=<url> to push" "info"
	fi
}

function execute_git_push() {
	display_alert "Pushing to ${target_branch}" "${target_repo_url}" "info"
	# @TODO: do NOT allow shallow trees here, we need the full history to be able to push
	GIT_SSH_COMMAND="ssh -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" "${push_command[@]}"
	display_alert "Done pushing to ${target_branch}" "${target_repo_url}" "info"

	# If GitHub, link there to both the branch main view and History view
	if [[ -n "${PUSH_TO_GITHUB}" ]]; then
		display_alert "GitHub tree URL" "https://github.com/${PUSH_TO_GITHUB}/tree/${target_branch}" "info"
		display_alert "GitHub commits URL" "https://github.com/${PUSH_TO_GITHUB}/commits/${target_branch}" "info"
	fi
}
