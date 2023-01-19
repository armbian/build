function kernel_prepare_git() {
	[[ -z $KERNELSOURCE ]] && return 0 # do nothing if no kernel source... but again, why were we called then?

	display_alert "Downloading sources" "kernel" "git"

	GIT_FIXED_WORKDIR="${LINUXSOURCEDIR}" \
		GIT_PRE_FETCH_HOOK=kernel_prepare_git_pre_fetch_tags \
		GIT_BARE_REPO_FOR_WORKTREE="${kernel_git_bare_tree}" \
		GIT_BARE_REPO_INITIAL_BRANCH="master" \
		fetch_from_repo "$KERNELSOURCE" "kernel:${KERNEL_MAJOR_MINOR}" "$KERNELBRANCH" "yes"
	# second parameter, "dir", is ignored, since we've passed GIT_FIXED_WORKDIR
}

function kernel_cleanup_bundle_artifacts() {
	declare git_bundles_dir="${SRC}/cache/git-bundles/kernel"

	if [[ -d "${git_bundles_dir}" ]]; then
		display_alert "Cleaning up Kernel git bundle artifacts" "no longer needed" "cachehit"
		run_host_command_logged rm -rf "${git_bundles_dir}"
	fi

	return 0
}
