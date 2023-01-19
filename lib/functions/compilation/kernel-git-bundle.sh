# This is NOT run under do_with_retries.
function download_git_kernel_bundle() {
	# See https://mirrors.edge.kernel.org/pub/scm/.bundles/pub/scm/linux/kernel/git/

	# rpardini: I'm a bit undecided about using the stable bundle (5gb) or the Linus bundle (3gb)
	# the stable seems much better at the end of the day.
	declare bundle_type="${bundle_type:-"stable"}" linux_clone_bundle_url=""
	case "${bundle_type}" in
		stable)
			display_alert "Using Kernel bundle" "${bundle_type}" "debug"
			linux_clone_bundle_url="https://mirrors.edge.kernel.org/pub/scm/.bundles/pub/scm/linux/kernel/git/stable/linux/clone.bundle"
			;;
		linus)
			display_alert "Using Kernel bundle" "${bundle_type}" "debug"
			linux_clone_bundle_url="https://mirrors.edge.kernel.org/pub/scm/.bundles/pub/scm/linux/kernel/git/torvalds/linux/clone.bundle"
			;;
	esac

	declare git_bundles_dir="${SRC}/cache/git-bundles/kernel"
	run_host_command_logged mkdir -pv "${git_bundles_dir}"

	# defines outer scope value
	linux_kernel_clone_bundle_file="${git_bundles_dir}/linux-${bundle_type}.bundle"
	declare linux_kernel_clone_bundle_file_tmp="${linux_kernel_clone_bundle_file}.tmp"

	# if the file already exists, do nothing
	if [[ -f "${linux_kernel_clone_bundle_file}" ]]; then
		display_alert "Kernel bundle already exists" "${bundle_type}" "cachehit"
		return 0
	fi

	# download into the tmp_file until it works, then rename to final; use axel.
	do_with_retries 5 kernel_download_bundle_with_axel

	# move into place, only if everything worked, retried or not.
	run_host_command_logged mv -v "${linux_kernel_clone_bundle_file_tmp}" "${linux_kernel_clone_bundle_file}"

	return 0
}


function kernel_download_bundle_with_axel() {
	display_alert "Downloading Kernel bundle" "${bundle_type}; this might take a long time" "info"
	declare -a verbose_params=()
	if_user_on_terminal_and_not_logging_add verbose_params "--verbose" "--alternate"
	if_user_not_on_terminal_or_is_logging_add verbose_params "--quiet"
	run_host_command_logged axel "${verbose_params[@]}" "--output=${linux_kernel_clone_bundle_file_tmp}" \
		"${linux_clone_bundle_url}"
}

function kernel_prepare_bare_repo_from_bundle() {
	kernel_git_bare_tree="${SRC}/cache/git-bare/kernel" # sets the outer scope variable
	declare kernel_git_bare_tree_done_marker="${kernel_git_bare_tree}/.git/armbian-bare-tree-done"

	if [[ ! -d "${kernel_git_bare_tree}" || ! -f "${kernel_git_bare_tree_done_marker}" ]]; then
		if [[ -d "${kernel_git_bare_tree}" ]]; then
			display_alert "Removing old kernel bare tree" "${kernel_git_bare_tree}" "info"
			rm -rf "${kernel_git_bare_tree}"
		fi

		# now, make sure we've the bundle downloaded correctly...
		# this defines linux_kernel_clone_bundle_file
		declare linux_kernel_clone_bundle_file
		download_git_kernel_bundle

		# fetch it, completely, into the bare tree; use clone, not fetch.
		display_alert "Cloning from bundle into bare tree" "this might take a very long time" "info"
		declare -a verbose_params=() && if_user_on_terminal_and_not_logging_add verbose_params "--verbose" "--progress"
		run_host_command_logged git clone "${verbose_params[@]}" --tags --no-checkout \
			"${linux_kernel_clone_bundle_file}" "${kernel_git_bare_tree}"

		# write the marker file
		touch "${kernel_git_bare_tree_done_marker}"
	fi

	return 0
}
