#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function compile_kernel() {
	declare kernel_work_dir="${SRC}/cache/sources/${LINUXSOURCEDIR}"
	display_alert "Kernel build starting" "${LINUXSOURCEDIR}" "info"

	# Prepare the git bare repo for the kernel; shared between all kernel builds
	declare kernel_git_bare_tree
	declare git_bundles_dir="${SRC}/cache/git-bundles/kernel"

	# @TODO: have a way to actually use this. It's inefficient, but might be the only way for people without ORAS/OCI for some reason.
	# Important: for the bundle version, gotta use "do_with_logging_unless_user_terminal" otherwise floods logs.
	# alternative # LOG_SECTION="kernel_prepare_bare_repo_from_bundle" do_with_logging_unless_user_terminal do_with_hooks \
	# alternative # 	kernel_prepare_bare_repo_from_bundle # this sets kernel_git_bare_tree

	# @TODO: Decide which kind of gitball to use: shallow or full.
	declare bare_tree_done_marker_file=".git/armbian-bare-tree-done"
	declare git_bundles_dir
	declare git_kernel_ball_fn
	declare git_kernel_oras_ref
	kernel_prepare_bare_repo_decide_shallow_or_full # sets kernel_git_bare_tree, git_bundles_dir, git_kernel_ball_fn, git_kernel_oras_ref

	LOG_SECTION="kernel_prepare_bare_repo_from_oras_gitball" do_with_logging do_with_hooks \
		kernel_prepare_bare_repo_from_oras_gitball # this sets kernel_git_bare_tree

	# prepare the working copy; this is the actual kernel source tree for this build
	declare checked_out_revision_ts="" checked_out_revision="undetermined" # set by fetch_from_repo
	LOG_SECTION="kernel_prepare_git" do_with_logging_unless_user_terminal do_with_hooks kernel_prepare_git

	# Capture date variables set by fetch_from_repo; it's the date of the last kernel revision
	declare kernel_git_revision="${checked_out_revision}"
	declare kernel_base_revision_ts="${checked_out_revision_ts}"
	declare kernel_base_revision_date # Used for KBUILD_BUILD_TIMESTAMP in make.
	kernel_base_revision_date="$(LC_ALL=C date -d "@${kernel_base_revision_ts}")"
	display_alert "Using Kernel git revision" "${kernel_git_revision} at '${kernel_base_revision_date}'"

	# Possibly 'make clean'.
	LOG_SECTION="kernel_maybe_clean" do_with_logging do_with_hooks kernel_maybe_clean

	# Patching.
	declare hash pre_patch_version
	kernel_main_patching # has it's own logging sections inside

	# Stop after patching;
	if [[ "${PATCH_ONLY}" == yes ]]; then
		display_alert "PATCH_ONLY is set, stopping." "PATCH_ONLY=yes and patching success" "cachehit"
		return 0
	fi

	# Stop after creating patches.
	if [[ "${CREATE_PATCHES}" == yes ]]; then
		display_alert "Stopping after creating kernel patch" "" "cachehit"
		return 0
	fi

	# patching worked, it's a good enough indication the git-bundle worked;
	# let's clean up the git-bundle cache, since the git-bare cache is proven working.
	LOG_SECTION="kernel_cleanup_bundle_artifacts" do_with_logging do_with_hooks kernel_cleanup_bundle_artifacts

	# re-read kernel version after patching
	declare version
	version=$(grab_version "$kernel_work_dir")
	display_alert "Compiling $BRANCH kernel" "$version" "info"

	# determine the toolchain
	declare toolchain
	LOG_SECTION="kernel_determine_toolchain" do_with_logging do_with_hooks kernel_determine_toolchain

	kernel_config # has it's own logging sections inside

	# Stop after configuring kernel, but only if using a specific CLI command ("kernel-config").
	# Normal "KERNEL_CONFIGURE=yes" (during image build) is still allowed.
	if [[ "${KERNEL_CONFIGURE}" == yes && "${ARMBIAN_COMMAND}" == "kernel-config" ]]; then
		display_alert "Stopping after configuring kernel" "" "cachehit"
		return 0
	fi

	# build via make and package .debs; they're separate sub-steps
	kernel_prepare_build_and_package # has it's own logging sections inside

	display_alert "Done with" "kernel compile" "debug"

	return 0
}

function kernel_maybe_clean() {
	if [[ $CLEAN_LEVEL == *make-kernel* ]]; then
		display_alert "Cleaning Kernel tree - CLEAN_LEVEL contains 'make-kernel'" "$LINUXSOURCEDIR" "info"
		(
			cd "${kernel_work_dir}" || exit_with_error "Can't cd to kernel_work_dir: ${kernel_work_dir}"
			run_host_command_logged git clean -xfdq # faster & more efficient than 'make clean'
		)
	else
		display_alert "Not cleaning Kernel tree; use CLEAN_LEVEL=make-kernel if needed" "CLEAN_LEVEL=${CLEAN_LEVEL}" "debug"
	fi
}

function kernel_prepare_build_and_package() {
	declare -a build_targets
	declare kernel_dest_install_dir
	declare -a install_make_params_quoted
	declare -A kernel_install_dirs

	build_targets=("all") # "All" builds the vmlinux/Image/Image.gz default for the ${ARCH}
	build_targets+=("${KERNEL_IMAGE_TYPE}")
	declare cleanup_id="" kernel_dest_install_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "k" cleanup_id kernel_dest_install_dir # namerefs

	# define dict with vars passed and target directories
	declare -A kernel_install_dirs=(
		["INSTALL_PATH"]="${kernel_dest_install_dir}/image/boot"  # Used by `make install`
		["INSTALL_MOD_PATH"]="${kernel_dest_install_dir}/modules" # Used by `make modules_install`
		#["INSTALL_HDR_PATH"]="${kernel_dest_install_dir}/libc_headers" # Used by `make headers_install` - disabled, only used for libc headers
	)

	[ -z "${SRC_LOADADDR}" ] || install_make_params_quoted+=("${SRC_LOADADDR}") # For uImage
	# @TODO: Only combining `install` and `modules_install` enable mixed-build and __build_one_by_one
	# We should spilt the `build` and `install` into two make steps as the kernel required
	build_targets+=("install" "${KERNEL_INSTALL_TYPE:-install}")

	build_targets+=("modules_install") # headers_install disabled, only used for libc headers
	if [[ "${KERNEL_BUILD_DTBS:-yes}" == "yes" ]]; then
		display_alert "Kernel build will produce DTBs!" "DTBs YES" "debug"
		build_targets+=("dtbs_install")
		kernel_install_dirs+=(["INSTALL_DTBS_PATH"]="${kernel_dest_install_dir}/dtbs") # Used by `make dtbs_install`
	fi

	# loop over the keys above, get the value, create param value in array; also mkdir the dir
	local dir_key
	for dir_key in "${!kernel_install_dirs[@]}"; do
		local dir="${kernel_install_dirs["${dir_key}"]}"
		local value="${dir_key}=${dir}"
		mkdir -p "${dir}"
		install_make_params_quoted+=("${value}")
	done

	# Fire off the build & package
	LOG_SECTION="kernel_build" do_with_logging do_with_hooks kernel_build

	# prepare a target dir for the shared, produced kernel .debs, across image/dtb/headers
	declare cleanup_id_debs="" kernel_debs_temp_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "kd" cleanup_id_debs kernel_debs_temp_dir # namerefs

	LOG_SECTION="kernel_package" do_with_logging do_with_hooks kernel_package

	# This deploys to DEB_STORAGE...
	LOG_SECTION="kernel_deploy_pkg" do_with_logging do_with_hooks kernel_deploy_pkg

	done_with_temp_dir "${cleanup_id_debs}" # changes cwd to "${SRC}" and fires the cleanup function early
	done_with_temp_dir "${cleanup_id}"      # changes cwd to "${SRC}" and fires the cleanup function early
}

function kernel_build() {
	local ts=${SECONDS}
	cd "${kernel_work_dir}" || exit_with_error "Can't cd to kernel_work_dir: ${kernel_work_dir}"

	display_alert "Building kernel" "${LINUXFAMILY} ${LINUXCONFIG} ${build_targets[*]}" "info"
	# make_filter="| grep --line-buffered -v -e 'LD' -e 'AR' -e 'INSTALL' -e 'SIGN' -e 'XZ' " \ # @TODO this will be summarised in the log file eventually, but shown in realtime in screen
	do_with_ccache_statistics \
		run_kernel_make_long_running "${install_make_params_quoted[@]@Q}" "${build_targets[@]}" # "V=1" # "-s" silent mode, "V=1" verbose mode

	display_alert "Kernel built in" "$((SECONDS - ts)) seconds - ${version}-${LINUXFAMILY}" "info"
}

function kernel_package() {
	local ts=${SECONDS}
	cd "${kernel_debs_temp_dir}" || exit_with_error "Can't cd to kernel_debs_temp_dir: ${kernel_debs_temp_dir}"
	cd "${kernel_work_dir}" || exit_with_error "Can't cd to kernel_work_dir: ${kernel_work_dir}"
	display_alert "Packaging kernel" "${LINUXFAMILY} ${LINUXCONFIG}" "info"
	prepare_kernel_packaging_debs "${kernel_work_dir}" "${kernel_dest_install_dir}" "${version}" kernel_install_dirs
	display_alert "Kernel packaged in" "$((SECONDS - ts)) seconds - ${version}-${LINUXFAMILY}" "info"
}

function kernel_deploy_pkg() {
	: "${kernel_debs_temp_dir:?kernel_debs_temp_dir is not set}"
	run_host_command_logged rsync -v --remove-source-files -r "${kernel_debs_temp_dir}"/*.deb "${DEB_STORAGE}/"
}
