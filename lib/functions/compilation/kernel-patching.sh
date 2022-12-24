#!/usr/bin/env bash

function kernel_main_patching_python() {
	prepare_pip_packages_for_python_tools

	# outer scope variables
	declare -I kernel_drivers_patch_file kernel_drivers_patch_hash

	declare patch_debug="${SHOW_DEBUG:-${DEBUG_PATCHING:-"no"}}"
	declare temp_file_for_output="$(mktemp)" # Get a temporary file for the output.
	# array with all parameters; will be auto-quoted by bash's @Q modifier below
	declare -a params_quoted=(
		"LOG_DEBUG=${patch_debug}"                            # Logging level for python.
		"SRC=${SRC}"                                          # Armbian root
		"OUTPUT=${temp_file_for_output}"                      # Output file for the python script.
		"ASSET_LOG_BASE=$(print_current_asset_log_base_file)" # base file name for the asset log; to write .md summaries.
		"PATCH_TYPE=kernel"                                   # or, u-boot, or, atf
		"PATCH_DIRS_TO_APPLY=${KERNELPATCHDIR}"               # A space-separated list of directories to apply...
		"USERPATCHES_PATH=${USERPATCHES_PATH}"                # Needed to find the userpatches.
		#"BOARD="                                             # BOARD is needed for the patchset selection logic; mostly for u-boot. empty for kernel.
		#"TARGET="                                            # TARGET is need for u-boot's SPI/SATA etc selection logic. empty for kernel
		# What to do?
		"APPLY_PATCHES=yes"                      # Apply the patches to the filesystem. Does not imply git commiting. If no, still exports the hash.
		"PATCHES_TO_GIT=${PATCHES_TO_GIT:-no}"   # Commit to git after applying the patches.
		"REWRITE_PATCHES=${REWRITE_PATCHES:-no}" # Rewrite the original patch files after git commiting.
		# Git dir, revision, and target branch
		"GIT_WORK_DIR=${kernel_work_dir}"                                # "Where to apply patches?"
		"BASE_GIT_REVISION=${kernel_git_revision}"                       # The revision we're building/patching. Python will reset and clean to this.
		"BRANCH_FOR_PATCHES=kernel-${LINUXFAMILY}-${KERNEL_MAJOR_MINOR}" # When applying patches-to-git, use this branch.
		# Lenience: allow problematic patches to be applied.
		"ALLOW_RECREATE_EXISTING_FILES=yes"    # Allow patches to recreate files that already exist.
		"GIT_ARCHEOLOGY=${GIT_ARCHEOLOGY:-no}" # Allow git to do some archaeology to find the original patch's owners
		# Pass the maintainer info, used for commits.
		"MAINTAINER_NAME=${MAINTAINER}"      # Name of the maintainer
		"MAINTAINER_EMAIL=${MAINTAINERMAIL}" # Email of the maintainer
		# Pass in the drivers extra patches and hashes; will be applied _first_, before series.
		"EXTRA_PATCH_FILES_FIRST=${kernel_drivers_patch_file}"  # Is a space-separated list.
		"EXTRA_PATCH_HASHES_FIRST=${kernel_drivers_patch_hash}" # Is a space-separated list.
	)
	display_alert "Calling Python patching script" "for kernel" "info"
	run_host_command_logged env -i "${params_quoted[@]@Q}" python3 "${SRC}/lib/tools/patching.py"
	run_host_command_logged cat "${temp_file_for_output}"
	# shellcheck disable=SC1090
	source "${temp_file_for_output}" # SOURCE IT!
	run_host_command_logged rm -f "${temp_file_for_output}"
	return 0
}

function kernel_main_patching() {
	# kernel_drivers_create_patches will fill the variables below
	declare kernel_drivers_patch_file kernel_drivers_patch_hash
	LOG_SECTION="kernel_drivers_create_patches" do_with_logging do_with_hooks kernel_drivers_create_patches "${kernel_work_dir}" "${kernel_git_revision}"

	# Python patching will git reset to the kernel SHA1 git revision, and remove all untracked files.
	LOG_SECTION="kernel_main_patching_python" do_with_logging do_with_hooks kernel_main_patching_python

	# The old way...
	#LOG_SECTION="kernel_prepare_patching" do_with_logging do_with_hooks kernel_prepare_patching
	#LOG_SECTION="kernel_patching" do_with_logging do_with_hooks kernel_patching

	# STOP HERE, for cli support for patching tools.
	if [[ "${PATCH_ONLY}" == "yes" ]]; then
		return 0
	fi

	# Interactive!!!
	[[ $CREATE_PATCHES == yes ]] && userpatch_create "kernel" # create patch for manual source changes

	return 0 # there is a shortcircuit above
}

function kernel_prepare_patching() {
	if [[ $USE_OVERLAYFS == yes ]]; then # @TODO: when is this set to yes?
		display_alert "Using overlayfs_wrapper" "kernel_${LINUXFAMILY}_${BRANCH}" "debug"
		kernel_work_dir=$(overlayfs_wrapper "wrap" "$SRC/cache/sources/$LINUXSOURCEDIR" "kernel_${LINUXFAMILY}_${BRANCH}")
	fi
	cd "${kernel_work_dir}" || exit

	# @TODO: why would we delete localversion?
	# @TODO: it should be the opposite, writing localversion to disk, _instead_ of passing it via make.
	# @TODO: if it turns out to be the case, do a commit with it... (possibly later, after patching?)
	rm -f localversion

	# read kernel version
	version=$(grab_version "$kernel_work_dir")
	pre_patch_version="${version}"
	display_alert "Pre-patch kernel version" "${pre_patch_version}" "debug"

	# read kernel git hash
	hash=$(git --git-dir="$kernel_work_dir"/.git rev-parse HEAD)
}

function kernel_patching() {
	## Start kernel patching process.
	## There's a few objectives here:
	## - (always) produce a fasthash: represents "what would be done" (eg: md5 of a patch, crc32 of description).
	## - (optionally) execute modification against living tree (eg: apply a patch, copy a file, etc). only if `DO_MODIFY=yes`
	## - (always) call mark_change_commit with the description of what was done and fasthash.
	# shellcheck disable=SC2154 # declared in outer scope kernel_base_revision_mtime
	declare -i patch_minimum_target_mtime="${kernel_base_revision_mtime}"
	declare -i series_conf_mtime="${patch_minimum_target_mtime}"
	declare -i patch_dir_mtime="${patch_minimum_target_mtime}"
	display_alert "patch_minimum_target_mtime:" "${patch_minimum_target_mtime}" "debug"

	local patch_dir="${SRC}/patch/kernel/${KERNELPATCHDIR}"
	local series_conf="${patch_dir}/series.conf"

	# So the minimum date has to account for removed patches; if a patch was removed from disk, the only way to reflect that
	# is by looking at the parent directory's mtime, which will have been bumped.
	# So we take a look at the possible directories involved here (series.conf file, and ${KERNELPATCHDIR} dir itself)
	# and bump up the minimum date if that is the case.
	if [[ -f "${series_conf}" ]]; then
		series_conf_mtime=$(get_file_modification_time "${series_conf}")
		display_alert "series.conf mtime:" "${series_conf_mtime}" "debug"
		patch_minimum_target_mtime=$((series_conf_mtime > patch_minimum_target_mtime ? series_conf_mtime : patch_minimum_target_mtime))
		display_alert "patch_minimum_target_mtime after series.conf mtime:" "${patch_minimum_target_mtime}" "debug"
	fi

	if [[ -d "${patch_dir}" ]]; then
		patch_dir_mtime=$(get_dir_modification_time "${patch_dir}")
		display_alert "patch_dir mtime:" "${patch_dir_mtime}" "debug"
		patch_minimum_target_mtime=$((patch_dir_mtime > patch_minimum_target_mtime ? patch_dir_mtime : patch_minimum_target_mtime))
		display_alert "patch_minimum_target_mtime after patch_dir mtime:" "${patch_minimum_target_mtime}" "debug"
	fi

	# this prepares data, and possibly creates a git branch to receive the patches.
	initialize_fasthash "kernel" "${hash}" "${pre_patch_version}" "${kernel_work_dir}"
	fasthash_debug "init"

	# Apply a series of patches if a series file exists
	if [[ -f "${series_conf}" ]]; then
		display_alert "series.conf exists. Apply"
		fasthash_branch "patches-${KERNELPATCHDIR}-series.conf"
		apply_patch_series "${kernel_work_dir}" "${series_conf}" # applies a series of patches, read from a file. calls process_patch_file
	fi

	# applies a humongous amount of patches coming from github repos.
	# it's mostly conditional, and very complex.
	# @TODO: re-enable after finishing converting it with fasthash magic
	# apply_kernel_patches_for_drivers  "${kernel_work_dir}" "${version}" # calls process_patch_file and other stuff. there is A LOT of it.

	# @TODO: this is were "patch generation" happens?

	# Extension hook: patch_kernel_for_driver
	call_extension_method "patch_kernel_for_driver" <<- 'PATCH_KERNEL_FOR_DRIVER'
		*allow to add drivers/patch kernel for drivers before applying the family patches*
		Patch *series* (not normal family patches) are already applied.
		Useful for migrating EXTRAWIFI-related stuff to individual extensions.
		Receives `${version}` and `${kernel_work_dir}` as environment variables.
	PATCH_KERNEL_FOR_DRIVER

	# applies a series of patches, in directory order, from multiple directories (default/"user" patches)
	# @TODO: I believe using the $BOARD here is the most confusing thing in the whole of Armbian. It should be disabled.
	# @TODO: Armbian built kernels dont't vary per-board, but only per "$ARCH-$LINUXFAMILY-$BRANCH"
	# @TODO: allowing for board-specific kernel patches creates insanity. uboot is enough.
	fasthash_branch "patches-${KERNELPATCHDIR}-$BRANCH"
	advanced_patch "kernel" "$KERNELPATCHDIR" "$BOARD" "" "$BRANCH" "$LINUXFAMILY-$BRANCH" # calls process_patch_file, "target" is empty there

	fasthash_debug "finish"
	finish_fasthash "kernel" # this reports the final hash and creates git branch to build ID. All modifications commited.
}
