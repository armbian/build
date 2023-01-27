# This is not run under logging section.
function kernel_prepare_bare_repo_decide_shallow_or_full() {
	declare decision="not_yet_decided" decision_why="unknown"
	declare -i ask_for_user_confirmation=0
	declare cache_git_bare_dir="${SRC}/cache/git-bare"
	declare FULL_kernel_git_bare_tree="${cache_git_bare_dir}/kernel"                                  # for reuse below
	declare FULL_marker="git-bare/kernel/"                                                            # part of path of the full version; "magic string"
	declare SHALLOW_kernel_git_bare_tree="${cache_git_bare_dir}/shallow-kernel-${KERNEL_MAJOR_MINOR}" # for reuse below
	git_bundles_dir="${SRC}/cache/git-bundles/kernel"                                                 # set outer scope variable

	run_host_command_logged mkdir -p "${cache_git_bare_dir}"

	# We've two options here.
	# One is to use the full version, which is around 3gb. "linux-complete.git.tar" and _always_ useful
	# The other is to use the shallow version, which is around 300mb. "linux-shallow-6.1.git.tar". Not always useful, might end up unshallowing it later in some fetch.
	# How to decide which one to use?
	# @TODO: Zero: If on CI=true (Github Actions, Gitlab CI, etc): we wanna use shallow for hosted runners, and full for self-hosted runners.
	# First: if the working copy already exists and is valid: use whatever that used before.
	# Second: if the full version is already there, use it. It's the most complete, and serves all purposes.
	# Third: if the shallow version is already there, for the KERNEL_MAJOR_MINOR in question, use it.
	# Fourth: if none is there; decide based on common sense. The shallow tree is useful until we fetch something that makes it unshallow.
	#   - vendor kernels (looking at you, rockchip-rk3588) are a mess and will cause fetches to unshallow?
	#   - if free disk space on target is less than 32gb (magic number?) use the shallow. It won't fit otherwise.
	#   - if the target resides on `mmc` device, use the shallow. It's too much disk traffic otherwise.
	#   - TODO: might be we don't carry a shallow gitball in ghcr.io for the wanted version -- how to know?

	# validate kernel_work_dir is set
	[[ -z "${kernel_work_dir}" ]] && exit_with_error "kernel_work_dir is not set"
	[[ -z "${bare_tree_done_marker_file}" ]] && exit_with_error "bare_tree_done_marker_file is not set"

	# gather info about the storage device on which the bare tree would, or already does, reside
	# @TODO refactor this out of here
	# Find the type of device (mmc/nvme/scsi/etc) (not type of filesystem...) that ${cache_git_bare_dir} resides on.
	declare device_backing_dir
	device_backing_dir="$(findmnt --nofsroot -n -o SOURCE --target "${cache_git_bare_dir}")"
	declare -i device_backing_dir_is_slow=0
	# if device_backing_dir contains "mmc", set device_backing_dir_is_slow=1
	if [[ "${device_backing_dir}" == *"mmc"* ]]; then
		display_alert "Device backing ${cache_git_bare_dir} is eMMC/SD/etc" "${device_backing_dir}" "git"
		device_backing_dir_is_slow=1
	fi
	display_alert "Device backing ${cache_git_bare_dir}" "${device_backing_dir}" "git"

	# @TODO Refactor this out of here - many other places using similar
	# Get the free disk space for the ${cache_git_bare_dir}, in MiB.
	declare -i free_space_mib
	free_space_mib="$(df -BM --output=avail "${cache_git_bare_dir}" | tail -n 1 | sed 's/M//')"
	display_alert "Free space on ${cache_git_bare_dir}" "${free_space_mib} MiB" "git"

	if [[ "${decision}" == "not_yet_decided" ]]; then
		# First: if ${kernel_work_dir}/.git already exists, use whatever that used before, by reading its .git file.
		if [[ -f "${kernel_work_dir}/.git" ]]; then
			display_alert "Worktree .git file already exists" "${kernel_work_dir}/.git" "git"
			if grep -q "${FULL_marker}" "${kernel_work_dir}/.git"; then
				display_alert "Worktree .git file indicates full version bare" "${kernel_work_dir}/.git" "git"
				decision="full"
				decision_why="existing worktree points to full"
			else
				display_alert "Worktree .git file does NOT indicate full bare" "${kernel_work_dir}/.git" "git"
				decision="shallow"
				decision_why="existing worktree points to shallow"
			fi
		else
			display_alert "Worktree .git file does NOT exist" "${kernel_work_dir}/.git" "git"
		fi
	fi

	if [[ "${decision}" == "not_yet_decided" ]]; then
		# Second: if ${FULL_kernel_git_bare_tree} and ${FULL_kernel_git_bare_tree}/${bare_tree_done_marker_file} exists
		if [[ -d "${FULL_kernel_git_bare_tree}" && -f "${FULL_kernel_git_bare_tree}/${bare_tree_done_marker_file}" ]]; then
			display_alert "Full version bare tree exists and is ready to go" "${FULL_kernel_git_bare_tree}" "git"
			decision="full" # end of story
			decision_why="full version bare tree exists and is ready to go"
		else
			display_alert "Full version bare tree does NOT exist or is NOT ready to go" "${FULL_kernel_git_bare_tree}" "git"
		fi
	fi

	# simplest, via parameter/env var, something like KERNEL_GIT=shallow or KERNEL_GIT=full to force.
	declare forced_decision="${KERNEL_GIT:-"none"}"
	if [[ "${decision}" == "not_yet_decided" ]]; then
		case "${forced_decision,,}" in # lowercase
			shallow)
				display_alert "Forced shallow via" "KERNEL_GIT=shallow" "git"
				decision="shallow"
				decision_why="forced by KERNEL_GIT=shallow"
				;;

			full)
				display_alert "Forced full via" "KERNEL_GIT=full" "git"
				decision="full"
				decision_why="forced by KERNEL_GIT=full"
				;;
		esac
	elif [[ "${forced_decision}" != "none" && "${forced_decision}" != "${decision}" ]]; then
		display_alert "Can't change Kernel git from '${decision}' to '${forced_decision}'" "${decision_why}" "warn"
		countdown_and_continue_if_not_aborted 3
	fi

	# @TODO: using shallow for vendor kernels (eg rockchip-rk3588) is a bad idea. It's a mess and will cause fetches to unshallow.
	# So skip Third if family indicates so, via KERNEL_VENDOR_DO_NOT_SHALLOW=yes in config.

	if [[ "${decision}" == "not_yet_decided" ]]; then
		# Third: if ${SHALLOW_kernel_git_bare_tree} and ${SHALLOW_kernel_git_bare_tree}/${bare_tree_done_marker_file} exists
		if [[ -d "${SHALLOW_kernel_git_bare_tree}" && -f "${SHALLOW_kernel_git_bare_tree}/${bare_tree_done_marker_file}" ]]; then
			display_alert "Shallow bare tree for {KERNEL_MAJOR_MINOR} exists and is ready to go" "${SHALLOW_kernel_git_bare_tree}" "git"
			decision="shallow" # end of story
			decision_why="shallow ${KERNEL_MAJOR_MINOR} bare tree exists and is ready to go"
		else
			display_alert "Shallow bare tree for ${KERNEL_MAJOR_MINOR} does NOT exist or is NOT ready to go" "${SHALLOW_kernel_git_bare_tree}" "git"
		fi
	fi

	if [[ "${decision}" == "not_yet_decided" ]]; then
		ask_for_user_confirmation=1 # no tree exists, will be the first time. offer option for user to abort.

		# TODO "magic number" here, make configurable
		if [[ ${free_space_mib} -lt 32768 ]] || [[ ${device_backing_dir_is_slow} -eq 1 ]]; then
			decision="shallow"
			decision_why="slow storage device (${device_backing_dir}) or low disk space (${free_space_mib} MiB)"
		else
			decision="full"
			decision_why="fast storage device (${device_backing_dir}) and enough disk space (${free_space_mib} MiB)"
		fi
	fi

	display_alert "Using ${decision} Kernel bare tree for ${KERNEL_MAJOR_MINOR}" "${decision_why}" "info"

	declare base_oras_ref="ghcr.io/rpardini/armbian-git-shallow" # @TODO allow changing this
	declare estimated_dl_size_mib=0 benefits="" cons=""
	case "${decision}" in
		shallow)
			# Outer scope variables
			kernel_git_bare_tree="${SHALLOW_kernel_git_bare_tree}"
			git_kernel_ball_fn="linux-shallow-${KERNEL_MAJOR_MINOR}.git.tar"
			git_kernel_oras_ref="${base_oras_ref}/kernel-git-shallow-${KERNEL_MAJOR_MINOR}:latest"
			estimated_dl_size_mib=300
			benefits="smaller download, less disk space consumed"
			cons="less useful over time, no history, not shared across versions"
			;;

		*)
			# Outer scope variables
			kernel_git_bare_tree="${FULL_kernel_git_bare_tree}" # sets the outer scope variable
			git_kernel_ball_fn="linux-complete.git.tar"
			git_kernel_oras_ref="${base_oras_ref}/kernel-git:latest"
			estimated_dl_size_mib=2700
			benefits="more useful over time, full history, single tree across all versions"
			cons="bigger download, more disk space consumed"
			;;
	esac

	display_alert "kernel_git_bare_tree" "${kernel_git_bare_tree}" "git"
	display_alert "git_kernel_ball_fn" "${git_kernel_ball_fn}" "git"
	display_alert "git_kernel_oras_ref" "${git_kernel_oras_ref}" "git"
	display_alert "estimated_dl_size_mib" "${estimated_dl_size_mib}" "git"

	# if ask_for_user_confirmation -eq 1 and -t 1
	if [[ ${ask_for_user_confirmation} -eq 1 && -t 1 ]]; then
		echo "--------------------------------------------------------------------------------------------------------------------" >&2
		display_alert "Warning: no Kernel bare tree exists for version ${KERNEL_MAJOR_MINOR} - about to start downloading." "" "wrn"
		display_alert "Armbian is going to use a '${decision}' git tree, which is around" "${estimated_dl_size_mib}MiB" ""
		display_alert "This was decided due to" "${decision_why}" ""
		display_alert "Benefits of using a '${decision}' git tree" "${benefits}" "info"
		display_alert "Cons of using a '${decision}' git tree" "${cons}" "wrn"
		display_alert "You can abort now, and pass either KERNEL_GIT=full or KERNEL_GIT=shallow to force." "" "wrn"
		display_alert "If you want to abort" "press Ctrl+C before the countdown ends in 60 seconds" "wrn"
		display_alert "If you agree with the decision to use a '${decision}' git tree" "press any other key to continue" ""
		countdown_and_continue_if_not_aborted 60
	fi

	return 0

}

# This is run under the logging section, so, no interactive parts -- please.
function kernel_prepare_bare_repo_from_oras_gitball() {

	# validate kernel_git_bare_tree and bare_tree_done_marker_file are set
	if [[ -z "${kernel_git_bare_tree}" ]]; then
		exit_with_error "kernel_git_bare_tree is not set"
	fi
	if [[ -z "${bare_tree_done_marker_file}" ]]; then
		exit_with_error "bare_tree_done_marker_file is not set"
	fi

	declare kernel_git_bare_tree_done_marker="${kernel_git_bare_tree}/${bare_tree_done_marker_file}"

	if [[ ! -d "${kernel_git_bare_tree}" || ! -f "${kernel_git_bare_tree_done_marker}" ]]; then
		display_alert "Preparing bare kernel git tree" "this might take a long time" "info"

		if [[ -d "${kernel_git_bare_tree}" ]]; then
			display_alert "Removing old kernel bare tree" "${kernel_git_bare_tree}" "info"
			run_host_command_logged rm -rf "${kernel_git_bare_tree}"
		fi

		wait_for_disk_sync "before Kernel git tree download"

		# now, make sure we've the bundle downloaded correctly...
		# this defines linux_kernel_clone_bundle_file
		declare linux_kernel_clone_tar_file
		download_git_kernel_gitball_via_oras # sets linux_kernel_clone_tar_file or dies

		wait_for_disk_sync "before Kernel git extraction"

		# Just extract the tar_file into the "${kernel_git_bare_tree}" directory, no further work needed.
		run_host_command_logged mkdir -p "${kernel_git_bare_tree}"
		# @TODO chance of a pv thingy here?
		run_host_command_logged tar -xf "${linux_kernel_clone_tar_file}" -C "${kernel_git_bare_tree}"

		wait_for_disk_sync "after Kernel git extraction"

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

function download_git_kernel_gitball_via_oras() {
	# validate git_bundles_dir, git_kernel_ball_fn, and git_kernel_oras_ref are set
	if [[ -z "${git_bundles_dir}" ]]; then
		exit_with_error "git_bundles_dir is not set"
	fi
	if [[ -z "${git_kernel_ball_fn}" ]]; then
		exit_with_error "git_kernel_ball_fn is not set"
	fi
	if [[ -z "${git_kernel_oras_ref}" ]]; then
		exit_with_error "git_kernel_oras_ref is not set"
	fi

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
