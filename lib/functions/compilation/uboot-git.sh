function uboot_prepare_bare_repo() {
	uboot_git_bare_tree="${SRC}/cache/git-bare/u-boot" # sets the outer scope variable
	declare uboot_git_bare_tree_done_marker="${uboot_git_bare_tree}/.git/armbian-bare-tree-done"

	if [[ ! -d "${uboot_git_bare_tree}" || ! -f "${uboot_git_bare_tree_done_marker}" ]]; then
		if [[ -d "${uboot_git_bare_tree}" ]]; then
			display_alert "Removing old u-boot bare tree" "${uboot_git_bare_tree}" "info"
			rm -rf "${uboot_git_bare_tree}"
		fi

		# get the mainline u-boot repo completely; use clone, not fetch.
		display_alert "Cloning u-boot from mainline into bare tree" "this might take a somewhat-long time" "info"
		declare -a verbose_params=() && if_user_on_terminal_and_not_logging_add verbose_params "--verbose" "--progress"
		run_host_command_logged git clone "${verbose_params[@]}" --tags --no-checkout \
			"${MAINLINE_UBOOT_SOURCE}" "${uboot_git_bare_tree}"

		# write the marker file
		touch "${uboot_git_bare_tree_done_marker}"
	fi

	return 0
}

function uboot_prepare_git() {
	display_alert "Preparing git for u-boot" "BOOTSOURCE: ${BOOTSOURCE}" "debug"
	if [[ -n $BOOTSOURCE ]] && [[ "${BOOTSOURCE}" != "none" ]]; then
		# Prepare the git bare repo for u-boot.
		declare uboot_git_bare_tree
		uboot_prepare_bare_repo # this sets uboot_git_bare_tree
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
	fi
	return 0
}
