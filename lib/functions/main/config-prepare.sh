#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Full version, for building a full image (with BOARD); possibly interactive.
function prep_conf_main_build_single() {
	LOG_SECTION="config_early_init" do_with_conditional_logging config_early_init

	# if interactive, call prepare-host.sh::check_basic_host() early, to avoid disappointments later.
	if [[ -t 0 ]]; then
		check_basic_host
	fi

	# those are possibly interactive. interactive (dialog) and logging don't mix, for obvious reasons.
	interactive_config_prepare_terminal # init vars used for interactive
	config_possibly_interactive_kernel_board

	LOG_SECTION="config_source_board_file" do_with_conditional_logging config_source_board_file

	config_possibly_interactive_branch_release_desktop_minimal

	LOG_SECTION="config_pre_main" do_with_conditional_logging config_pre_main

	LOG_SECTION="do_main_configuration" do_with_conditional_logging do_main_configuration # This initializes the extension manager among a lot of other things, and call extension_prepare_config() hook

	interactive_desktop_main_configuration
	interactive_finish # cleans up vars used for interactive

	LOG_SECTION="do_extra_configuration" do_with_conditional_logging do_extra_configuration

	LOG_SECTION="config_post_main" do_with_conditional_logging config_post_main

	# Now, if NOT interactive, do some basic checks. If interactive, it has been done 20 lines above.
	if [[ ! -t 0 ]]; then
		LOG_SECTION="ni_check_basic_host" do_with_logging check_basic_host
	fi

	# can't aggregate here, since it needs a prepared host... mark to do it later.
	mark_aggregation_required_in_default_build_start

	display_alert "Configuration prepared for BOARD build" "${BOARD}.${BOARD_TYPE}" "info"
}

# Minimal, non-interactive version.
function prep_conf_main_minimal_ni() {
	# needed
	LOG_SECTION="config_early_init" do_with_conditional_logging config_early_init

	# needed for most stuff, but not for configdump
	if [[ "${skip_host_config:-"no"}" != "yes" ]]; then
		if [[ "${CONFIG_DEFS_ONLY}" != "yes" ]]; then
			check_basic_host
		fi
	fi

	# needed for BOARD= builds.
	if [[ "${use_board:-"no"}" == "yes" ]]; then
		LOG_SECTION="config_source_board_file" do_with_conditional_logging config_source_board_file
		allow_no_family="no"
		skip_kernel="no" # contentious: we could do u-boot without kernel...
	fi

	# not needed, doesnt hurt; might be moved to aggregation
	LOG_SECTION="config_pre_main" do_with_conditional_logging config_pre_main

	# Required, but does stuff it maybe shouldn't
	allow_no_family="${allow_no_family:-"yes"}" \
		LOG_SECTION="do_main_configuration" do_with_conditional_logging do_main_configuration # This initializes the extension manager among a lot of other things, and call extension_prepare_config() hook

	# Required: does a lot of stuff and extension_prepare_config() hook
	LOG_SECTION="do_extra_configuration" do_with_conditional_logging do_extra_configuration

	# Calculates CHOSEN_xxx's and optional kernel stuff; runs extension_finish_config() hook
	skip_kernel="${skip_kernel:-"yes"}" \
		LOG_SECTION="config_post_main" do_with_conditional_logging config_post_main

	display_alert "Minimal configuration prepared for build" "prep_conf_main_minimal_ni" "info"
}

# Lean version, for building rootfs, that doesn't need BOARD/BOARDFAMILY; never interactive.
function prep_conf_main_only_rootfs_ni() {
	prep_conf_main_minimal_ni

	# can't aggregate here, since it needs a prepared host... mark to do it later.
	mark_aggregation_required_in_default_build_start

	display_alert "Configuration prepared for minimal+rootfs" "prep_conf_main_only_rootfs_ni" "info"
}

function config_source_board_file() {
	declare -a BOARD_SOURCE_FILES=()
	# This has to be syncronized with get_list_of_all_buildable_boards() in interactive.sh!
	# I used to re-use that code here, but it's very slow, specially for CONFIG_DEFS_ONLY.
	local -a board_types=("conf" "wip" "csc" "eos" "tvb")
	local -a board_file_paths=("${SRC}/config/boards" "${USERPATCHES_PATH}/config/boards")
	declare board_file_path board_type full_board_file first_board_type_found
	for board_file_path in "${board_file_paths[@]}"; do
		[[ ! -d "${board_file_path}" ]] && continue
		for board_type in "${board_types[@]}"; do
			full_board_file="${board_file_path}/${BOARD}.${board_type}"
			if [[ -f "${full_board_file}" ]]; then
				BOARD_SOURCE_FILES+=("${full_board_file}")
				[[ -z "${first_board_type_found}" ]] && first_board_type_found="${board_type}"
				break # only one board type considered, if found. @TODO: this might lead to confusion if both exist; detect and abort.
			fi
		done
	done

	# BOARD_TYPE is included in /etc/armbian-release and used for stuff board-side; make it global and readonly
	declare -g -r BOARD_TYPE="${first_board_type_found}" # so userpatches can't change support status of existing boards

	declare -a sourced_board_configs=()
	declare BOARD_SOURCE_FILE
	for BOARD_SOURCE_FILE in "${BOARD_SOURCE_FILES[@]}"; do # No quotes, so expand the space-delimited list
		display_alert "Sourcing board configuration" "${BOARD_SOURCE_FILE}" "info"
		# shellcheck source=/dev/null
		source "${BOARD_SOURCE_FILE}"
		sourced_board_configs+=("${BOARD_SOURCE_FILE}")
	done

	# Sanity check: if no board config was sourced, then the board name is invalid
	[[ ${#sourced_board_configs[@]} -eq 0 ]] && exit_with_error "No such BOARD '${BOARD}'; no board config file found."

	# Otherwise publish it as readonly global
	declare -g -r SOURCED_BOARD_CONFIGS_FILENAME_LIST="${sourced_board_configs[*]}"

	# this is (100%?) rewritten by family config!
	# answer: this defaults LINUXFAMILY to BOARDFAMILY. that... shouldn't happen, extensions might change it too.
	# @TODO: better to check for empty after sourcing family config and running extensions, *warning about it*, and only then default to BOARDFAMILY.
	# this sourced the board config. do_main_configuration will source the (BOARDFAMILY) family file.
	LINUXFAMILY="${BOARDFAMILY}"

	# Lets make some variables readonly after sourcing the board file.
	# We don't want anything changing them, it's exclusively for board config.
	# @TODO: ok but then we need some way to add packages simply via command line or config. ADD_PACKAGES_IMAGE="foo,bar"?
	declare -g -r PACKAGE_LIST_BOARD="${PACKAGE_LIST_BOARD}"
	declare -g -r PACKAGE_LIST_BOARD_REMOVE="${PACKAGE_LIST_BOARD_REMOVE}"

	[[ -z $KERNEL_TARGET ]] && exit_with_error "Board ('${BOARD}') configuration does not define valid kernel config"

	return 0 # shortcircuit above
}

function config_early_init() {

	# default umask for root is 022 so parent directories won't be group writeable without this
	# this is used instead of making the chmod in prepare_host() recursive
	umask 002

	# Warnings mitigation
	[[ -z $LANGUAGE ]] && export LANGUAGE="en_US:en"      # set to english if not set
	[[ -z $CONSOLE_CHAR ]] && export CONSOLE_CHAR="UTF-8" # set console to UTF-8 if not set

	declare -g SHOW_WARNING=yes # If you try something that requires EXPERT=yes.

	display_alert "Starting single build process" "${BOARD:-"no BOARD set"}" "info"

	return 0 # protect against eventual shortcircuit above
}

function config_pre_main() {
	#prevent conflicting setup
	if [[ $BUILD_DESKTOP == "yes" ]]; then
		BUILD_MINIMAL=no
		SELECTED_CONFIGURATION="desktop"
	elif [[ $BUILD_MINIMAL != "yes" || -z "${BUILD_MINIMAL}" ]]; then
		BUILD_MINIMAL=no # Just in case BUILD_MINIMAL is not defined
		BUILD_DESKTOP=no
		SELECTED_CONFIGURATION="cli_standard"
	elif [[ $BUILD_MINIMAL == "yes" ]]; then
		BUILD_DESKTOP=no
		PLYMOUTH=no
		SELECTED_CONFIGURATION="cli_minimal"
	fi

	return 0 # shortcircuit above
}

function config_post_main() {
	if [[ $COMPRESS_OUTPUTIMAGE == "" || $COMPRESS_OUTPUTIMAGE == no ]]; then
		COMPRESS_OUTPUTIMAGE="sha,img"
	fi

	if [[ "$BETA" == "yes" ]]; then
		IMAGE_TYPE=nightly
	elif [ "$BETA" == "no" ] || [ "$RC" == "yes" ]; then
		IMAGE_TYPE=stable
	else
		IMAGE_TYPE=user-built
	fi

	declare -g BOOTSOURCEDIR
	BOOTSOURCEDIR="u-boot-worktree/${BOOTDIR}/$(branch2dir "${BOOTBRANCH}")"
	if [[ -n $ATFSOURCE ]]; then
		declare -g ATFSOURCEDIR
		ATFSOURCEDIR="${ATFDIR}/$(branch2dir "${ATFBRANCH}")"
	fi

	declare -g CHOSEN_UBOOT=linux-u-boot-${BRANCH}-${BOARD}

	# So for kernel full cached rebuilds.
	# We wanna be able to rebuild kernels very fast. so it only makes sense to use a dir for each built kernel.
	# That is the "default" layout; there will be as many source dirs as there are built kernel debs.
	# But, it really makes much more sense if the major.minor (such as 5.10, 5.15, or 4.4) of kernel has its own
	# tree. So in the end:
	# <arch>-<major.minor>[-<family>]
	# So we gotta explictly know the major.minor to be able to do that scheme.
	# If we don't know, we could use BRANCH as reference, but that changes over time, and leads to wastage.
	if [[ "${skip_kernel:-"no"}" != "yes" ]]; then
		if [[ -n "${KERNELSOURCE}" ]]; then
			if [[ "x${KERNEL_MAJOR_MINOR}x" == "xx" ]]; then
				exit_with_error "BAD config, missing" "KERNEL_MAJOR_MINOR" "err"
			fi
			# assume the worst, and all surprises will be happy ones
			declare -g KERNEL_HAS_WORKING_HEADERS="no"

			# Parse/validate the the major, bail if no match
			declare -i KERNEL_MAJOR_MINOR_MAJOR=${KERNEL_MAJOR_MINOR%%.*}
			declare -i KERNEL_MAJOR_MINOR_MINOR=${KERNEL_MAJOR_MINOR#*.}

			if [[ "${KERNEL_MAJOR_MINOR_MAJOR}" -ge 6 ]] || [[ "${KERNEL_MAJOR_MINOR_MAJOR}" -ge 5 && "${KERNEL_MAJOR_MINOR_MINOR}" -ge 4 ]]; then # We support 6.x, and 5.x from 5.4
				declare -g KERNEL_HAS_WORKING_HEADERS="yes"
				declare -g KERNEL_MAJOR="${KERNEL_MAJOR_MINOR_MAJOR}"
			elif [[ "${KERNEL_MAJOR_MINOR_MAJOR}" -eq 4 && "${KERNEL_MAJOR_MINOR_MINOR}" -ge 19 ]]; then
				declare -g KERNEL_MAJOR=4 # We support 4.19+ (less than 5.0) is supported
			elif [[ "${KERNEL_MAJOR_MINOR_MAJOR}" -eq 4 && "${KERNEL_MAJOR_MINOR_MINOR}" -ge 4 ]]; then
				declare -g KERNEL_MAJOR=4 # We support 4.x from 4.4
			else
				# If you think you can patch packaging to support this, you're probably right. Is _worth_ it though?
				exit_with_error "Kernel series unsupported" "'${KERNEL_MAJOR_MINOR}' is unsupported, or bad config"
			fi

			# Default LINUXSOURCEDIR:
			declare -g LINUXSOURCEDIR="linux-kernel-worktree/${KERNEL_MAJOR_MINOR}__${LINUXFAMILY}__${ARCH}"

			# Allow adding to it with KERNEL_EXTRA_DIR
			if [[ "${KERNEL_EXTRA_DIR}" != "" ]]; then
				declare -g LINUXSOURCEDIR="${LINUXSOURCEDIR}__${KERNEL_EXTRA_DIR}"
				display_alert "Using kernel extra dir: '${KERNEL_EXTRA_DIR}'" "LINUXSOURCEDIR: ${LINUXSOURCEDIR}" "debug"
			fi
		else
			declare -g KERNEL_HAS_WORKING_HEADERS="yes" # I assume non-Armbian kernels have working headers, eg: Debian/Ubuntu generic do.
		fi
	else
		display_alert "Skipping kernel config" "skip_kernel=yes" "debug"
	fi

	if [[ -n "${BOOTCONFIG}" ]] && [[ "${BOOTCONFIG}" != "none" ]]; then
		declare -g ARMBIAN_WILL_BUILD_UBOOT=yes
	else
		declare -g ARMBIAN_WILL_BUILD_UBOOT=no
	fi

	display_alert "Extensions: finish configuration" "extension_finish_config" "debug"
	call_extension_method "extension_finish_config" <<- 'EXTENSION_FINISH_CONFIG'
		*allow extensions a last chance at configuration just before it is done*
		After kernel versions are set, package names determined, etc.
		This runs *late*, and is the final step before finishing configuration.
		Don't change anything not coming from other variables or meant to be configured by the user.
	EXTENSION_FINISH_CONFIG

	return 0 # protect against eventual shortcircuit above
}

# cli-bsp also uses this
function set_distribution_status() {
	local distro_support_desc_filepath="${SRC}/config/distributions/${RELEASE}/support"
	if [[ ! -f "${distro_support_desc_filepath}" ]]; then
		exit_with_error "Distribution dir '${distro_support_desc_filepath}' does not exist"
	else
		DISTRIBUTION_STATUS="$(cat "${distro_support_desc_filepath}")"
	fi

	[[ "${DISTRIBUTION_STATUS}" != "supported" ]] && [[ "${EXPERT}" != "yes" ]] && exit_with_error "Armbian ${RELEASE} is unsupported and, therefore, only available to experts (EXPERT=yes)"

	return 0 # due to last stmt above being a shortcircuit conditional
}

# Some utility functions
function branch2dir() {
	[[ "${1}" == "head" ]] && echo "HEAD" || echo "${1##*:}"
	return 0
}
