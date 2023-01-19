function download_git_kernel_gitball_via_oras() {
	declare git_bundles_dir="${SRC}/cache/git-bundles/kernel"
	declare git_kernel_ball_fn="linux-complete.git.tar"                                  # @TODO: shallow?
	declare git_kernel_oras_ref="ghcr.io/rpardini/armbian-git-shallow/kernel-git:latest" # @TODO: shallow?

	run_host_command_logged mkdir -p "${git_bundles_dir}" # this is later cleaned up by kernel_cleanup_bundle_artifacts()

	# defines outer scope value
	linux_kernel_clone_tar_file="${git_bundles_dir}/${git_kernel_ball_fn}"

	# if the file already exists, do nothing; it will only exist if successfully downloaded by ORAS
	if [[ -f "${linux_kernel_clone_tar_file}" ]]; then
		display_alert "Kernel git-tarball already exists" "${git_kernel_ball_fn}" "cachehit"
		return 0
	fi

	# do_with_retries 5 xxx ? -- no -- oras_pull_artifact_file should do it's own retries.
	oras_pull_artifact_file "${git_kernel_oras_ref}" "${git_bundles_dir}" "${git_kernel_ball_fn}"

	# sanity check
	if [[ ! -f "${linux_kernel_clone_tar_file}" ]]; then
		exit_with_error "Kernel git-tarball download failed ${linux_kernel_clone_tar_file}"
	fi

	return 0

}

function kernel_prepare_bare_repo_from_oras_gitball() {
	kernel_git_bare_tree="${SRC}/cache/git-bare/kernel" # sets the outer scope variable
	declare kernel_git_bare_tree_done_marker="${kernel_git_bare_tree}/.git/armbian-bare-tree-done"

	if [[ ! -d "${kernel_git_bare_tree}" || ! -f "${kernel_git_bare_tree_done_marker}" ]]; then
		display_alert "Preparing bare kernel git tree" "this might take a long time" "info"

		if [[ -d "${kernel_git_bare_tree}" ]]; then
			display_alert "Removing old kernel bare tree" "${kernel_git_bare_tree}" "info"
			run_host_command_logged rm -rf "${kernel_git_bare_tree}"
		fi

		# now, make sure we've the bundle downloaded correctly...
		# this defines linux_kernel_clone_bundle_file
		declare linux_kernel_clone_tar_file
		download_git_kernel_gitball_via_oras # sets linux_kernel_clone_tar_file or dies

		# Just extract the tar_file into the "${kernel_git_bare_tree}" directory, no further work needed.
		run_host_command_logged mkdir -p "${kernel_git_bare_tree}"
		# @TODO chance of a pv thingy here?
		run_host_command_logged tar -xf "${linux_kernel_clone_tar_file}" -C "${kernel_git_bare_tree}"

		# sanity check
		if [[ ! -d "${kernel_git_bare_tree}/.git" ]]; then
			exit_with_error "Kernel bare tree is missing .git directory ${kernel_git_bare_tree}"
		fi

		# write the marker file
		touch "${kernel_git_bare_tree_done_marker}"
	else
		display_alert "Kernel bare tree already exists" "${kernel_git_bare_tree}" "cachehit"
	fi

	git_ensure_safe_directory "${kernel_git_bare_tree}"

	return 0
}
