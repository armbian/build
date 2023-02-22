function kernel_prepare_git() {
	[[ -z $KERNELSOURCE ]] && return 0 # do nothing if no kernel source... but again, why were we called then?

	# validate kernel_git_bare_tree is set
	if [[ -z "${kernel_git_bare_tree}" ]]; then
		exit_with_error "kernel_git_bare_tree is not set"
	fi

	display_alert "Downloading sources" "kernel" "git"

	GIT_FIXED_WORKDIR="${LINUXSOURCEDIR}" \
		GIT_BARE_REPO_FOR_WORKTREE="${kernel_git_bare_tree}" \
		GIT_BARE_REPO_INITIAL_BRANCH="master" \
		fetch_from_repo "${KERNELSOURCE}" "kernel:${KERNEL_MAJOR_MINOR}" "${KERNELBRANCH}" "yes"
	# second parameter, "dir", is ignored, since we've passed GIT_FIXED_WORKDIR
}

function kernel_cleanup_bundle_artifacts() {
	[[ -z "${git_bundles_dir}" ]] && exit_with_error "git_bundles_dir is not set"

	if [[ -d "${git_bundles_dir}" ]]; then
		display_alert "Cleaning up Kernel git bundle artifacts" "no longer needed" "info"
		run_host_command_logged rm -rf "${git_bundles_dir}"
	fi

	return 0
}
