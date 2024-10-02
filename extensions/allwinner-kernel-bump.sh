#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Gunjan Gupta <gunjan@armbian.com>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

PREV_KERNEL_PATCH_DIR=none

function extension_prepare_config__prepare_kernel_patches() {
	if [[ ! ${LINUXFAMILY} == sunxi* ]] || [[ "${BRANCH}" != "edge" ]]; then
		exit_with_error "allwinner-kernel-bump extension must only be used with allwinner boards with edge kernel"
	fi

	if [[ ${ARMBIAN_RELAUNCHED} == "yes" ]]; then
		display_alert "allwinner-kernel-bump" "Checking new kernel version" "info"
		PREV_KERNEL_PATCH_DIR=${SRC}/patch/kernel/${KERNELPATCHDIR}
		declare -g KERNELBRANCH="branch:master"
		declare -A AKB_GIT_INFO=([GIT_SOURCE]="${KERNELSOURCE}" [GIT_REF]="${KERNELBRANCH}")
		run_memoized AKB_GIT_INFO "git2info" memoized_git_ref_to_info "include_makefile_body"
		declare -g KERNEL_MAJOR_MINOR=${AKB_GIT_INFO[MAKEFILE_FULL_VERSION]%.*}
		declare -g KERNELPATCHDIR="archive/sunxi-${KERNEL_MAJOR_MINOR}"
		display_alert "allwinner-kernel-bump" "New kernel version ${KERNEL_MAJOR_MINOR}" "info"
	fi
}

function extension_finish_config__prepare_megous_patches() {
	if [[ ${ARMBIAN_RELAUNCHED} == "yes" ]]; then
		declare bare_tree_done_marker_file=".git/armbian-bare-tree-done"
		declare kernel_git_bare_tree
		declare git_bundles_dir
		declare git_kernel_ball_fn
		declare git_kernel_oras_ref
		declare kernel_work_dir="${SRC}/cache/sources/${LINUXSOURCEDIR}"
		patch_dir_base="${SRC}/patch/kernel/${KERNELPATCHDIR}"
		patch_dir_megous="${patch_dir_base}/patches.megous"
		patch_dir_tmp="${patch_dir_base}/patches.megi"

		if [[ -d ${patch_dir_base} ]]; then
			display_alert "allwinner-kernel-bump" "Found existing kernel patch directory" "info"
			if [[ "${OVERWRITE_PATCHDIR:-no}" == "yes" ]]; then
				display_alert "allwinner-kernel-bump" "Removing as requested. Any manual changes will get overwritten" "info"
				rm -rf ${patch_dir_base}
			else
				display_alert "allwinner-kernel-bump" "Skipping kernel patch directory creation" "info"
				return 0
			fi
		fi

		display_alert "allwinner-kernel-bump" "Preparing kernel git tree" "info"
		kernel_prepare_bare_repo_decide_shallow_or_full
		kernel_prepare_bare_repo_from_oras_gitball
		kernel_prepare_git
		kernel_maybe_clean

		bundle_file="${git_bundles_dir}/linux-megous.bundle"
		bundle_url="https://xff.cz/kernels/git/orange-pi-active.bundle"

		display_alert "allwinner-kernel-bump" "Applying megous git bundle on kernel git tree" "info"
		run_host_command_logged mkdir -pv "${git_bundles_dir}"
		run_host_command_logged rm "${bundle_file}" || true
		do_with_retries 5 axel "--output=${bundle_file}" "${bundle_url}"
		run_host_command_logged git -C ${kernel_work_dir} fetch ${bundle_file} '+refs/heads/*:refs/remotes/megous/*'

		display_alert "allwinner-kernel-bump" "Initializing kernel patch directory using previous kernel patch dir" "info"
		run_host_command_logged cp -aR ${PREV_KERNEL_PATCH_DIR} ${patch_dir_base}

		# Removing older copy of megous patches and series.conf file
		run_host_command_logged rm -rf ${patch_dir_base}/patches.megous/*
		run_host_command_logged rm -f ${patch_dir_base}/series.{conf,megous}

		display_alert "allwinner-kernel-bump" "Extracting latest Megous patches" "info"
		megous_trees=("a83t-suspend" "af8133j" "anx" "audio" "axp" "cam" "drm"
			"err" "fixes" "mbus" "modem" "opi3" "pb" "pinetab" "pp" "ppkb" "samuel"
			"speed" "tbs-a711" "ths")

		run_host_command_logged mkdir -p ${patch_dir_megous} ${patch_dir_tmp}

		for tree in ${megous_trees[@]}; do
			run_host_command_logged "${SRC}"/tools/mk_format_patch ${kernel_work_dir} master..megous/${tree}-${KERNEL_MAJOR_MINOR} ${patch_dir_megous} sufix=megi
			run_host_command_logged cp ${patch_dir_megous}/* ${patch_dir_tmp}
			run_host_command_logged cat ${patch_dir_base}/series.megous ">>" ${patch_dir_base}/series.megi
		done

		run_host_command_logged cp ${patch_dir_tmp}/* ${patch_dir_megous}
		run_host_command_logged mv ${patch_dir_base}/series.megi ${patch_dir_base}/series.megous
		run_host_command_logged rm -rf ${patch_dir_tmp} ${patch_dir_base}/series.megi

		# Disable previously disabled patches
		grep '^-' ${PREV_KERNEL_PATCH_DIR}/series.megous | awk -F / '{print $NF}' | xargs -I {} sed -i "/\/{}/s/^/-/g" ${patch_dir_base}/series.megous

		display_alert "allwinner-kernel-bump" "Generating series.conf file" "info"
		run_host_command_logged cat ${patch_dir_base}/series.megous ">>" ${patch_dir_base}/series.conf
		run_host_command_logged cat ${patch_dir_base}/series.fixes ">>" ${patch_dir_base}/series.conf
		run_host_command_logged cat ${patch_dir_base}/series.armbian ">>" ${patch_dir_base}/series.conf
	fi
}
