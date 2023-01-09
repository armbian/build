#!/usr/bin/env bash

function prepare_and_config_main_build_single() {
	LOG_SECTION="config_early_init" do_with_conditional_logging config_early_init

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
	display_alert "Done with prepare_and_config_main_build_single" "${BOARD}.${BOARD_TYPE}" "info"
}

function config_source_board_file() {
	declare -a arr_all_board_names=()                                                                           # arrays
	declare -A dict_all_board_types=() dict_all_board_source_files=()                                           # dictionaries
	get_list_of_all_buildable_boards arr_all_board_names "" dict_all_board_types dict_all_board_source_files "" # invoke

	declare BOARD_TYPE="${dict_all_board_types["${BOARD}"]}"
	declare BOARD_SOURCE_FILES="${dict_all_board_source_files["${BOARD}"]}"
	declare BOARD_SOURCE_FILE

	declare -a sourced_board_configs=()
	for BOARD_SOURCE_FILE in ${BOARD_SOURCE_FILES}; do # No quotes, so expand the space-delimited list
		display_alert "Sourcing board configuration" "${BOARD_SOURCE_FILE}" "info"
		# shellcheck source=/dev/null
		source "${BOARD_SOURCE_FILE}"
		sourced_board_configs+=("${BOARD_SOURCE_FILE}")
	done

	# Sanity check: if no board config was sourced, then the board name is invalid
	[[ ${#sourced_board_configs[@]} -eq 0 ]] && exit_with_error "No such BOARD '${BOARD}'; no board config file found."

	LINUXFAMILY="${BOARDFAMILY}" # @TODO: wtf? why? this is (100%?) rewritten by family config!
	# this sourced the board config. do_main_configuration will source the family file.

	# Lets make some variables readonly.
	# We don't want anything changing them, it's exclusively for board config.
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
		SELECTED_CONFIGURATION="cli_minimal"
	fi

	[[ ${KERNEL_CONFIGURE} == prebuilt ]] && [[ -z ${REPOSITORY_INSTALL} ]] &&
		REPOSITORY_INSTALL="u-boot,kernel,bsp,armbian-zsh,armbian-config,armbian-bsp-cli,armbian-firmware${BUILD_DESKTOP:+,armbian-desktop,armbian-bsp-desktop}"

	return 0 # shortcircuit above
}

function config_post_main() {
	if [[ "$BETA" == "yes" ]]; then
		IMAGE_TYPE=nightly
	elif [ "$BETA" == "no" ] || [ "$RC" == "yes" ]; then
		IMAGE_TYPE=stable
	else
		IMAGE_TYPE=user-built
	fi

	declare -g BOOTSOURCEDIR="u-boot-worktree/${BOOTDIR}/$(branch2dir "${BOOTBRANCH}")"
	[[ -n $ATFSOURCE ]] && declare -g ATFSOURCEDIR="${ATFDIR}/$(branch2dir "${ATFBRANCH}")"

	declare -g BSP_CLI_PACKAGE_NAME="armbian-bsp-cli-${BOARD}${EXTRA_BSP_NAME}"
	declare -g BSP_CLI_PACKAGE_FULLNAME="${BSP_CLI_PACKAGE_NAME}_${REVISION}_${ARCH}"
	declare -g BSP_DESKTOP_PACKAGE_NAME="armbian-bsp-desktop-${BOARD}${EXTRA_BSP_NAME}"
	declare -g BSP_DESKTOP_PACKAGE_FULLNAME="${BSP_DESKTOP_PACKAGE_NAME}_${REVISION}_${ARCH}"

	declare -g CHOSEN_UBOOT=linux-u-boot-${BRANCH}-${BOARD}
	declare -g CHOSEN_KERNEL=linux-image-${BRANCH}-${LINUXFAMILY}
	declare -g CHOSEN_ROOTFS=${BSP_CLI_PACKAGE_NAME}
	declare -g CHOSEN_DESKTOP=armbian-${RELEASE}-desktop-${DESKTOP_ENVIRONMENT}
	declare -g CHOSEN_KSRC=linux-source-${BRANCH}-${LINUXFAMILY}
	declare -g CHOSEN_KERNEL_WITH_ARCH=${CHOSEN_KERNEL}-${ARCH} # Only for reporting purposes.

	# So for kernel full cached rebuilds.
	# We wanna be able to rebuild kernels very fast. so it only makes sense to use a dir for each built kernel.
	# That is the "default" layout; there will be as many source dirs as there are built kernel debs.
	# But, it really makes much more sense if the major.minor (such as 5.10, 5.15, or 4.4) of kernel has its own
	# tree. So in the end:
	# <arch>-<major.minor>[-<family>]
	# So we gotta explictly know the major.minor to be able to do that scheme.
	# If we don't know, we could use BRANCH as reference, but that changes over time, and leads to wastage.
	if [[ -n "${KERNELSOURCE}" ]]; then
		declare -g ARMBIAN_WILL_BUILD_KERNEL="${CHOSEN_KERNEL}-${ARCH}"
		if [[ "x${KERNEL_MAJOR_MINOR}x" == "xx" ]]; then
			exit_with_error "BAD config, missing" "KERNEL_MAJOR_MINOR" "err"
		fi
		# assume the worst, and all surprises will be happy ones
		declare -g KERNEL_HAS_WORKING_HEADERS="no"
		declare -g KERNEL_HAS_WORKING_HEADERS_FULL_SOURCE="no"

		# Parse/validate the the major, bail if no match
		declare -i KERNEL_MAJOR_MINOR_MAJOR=${KERNEL_MAJOR_MINOR%%.*}
		declare -i KERNEL_MAJOR_MINOR_MINOR=${KERNEL_MAJOR_MINOR#*.}

		if [[ "${KERNEL_MAJOR_MINOR_MAJOR}" -ge 6 ]] || [[ "${KERNEL_MAJOR_MINOR_MAJOR}" -ge 5 && "${KERNEL_MAJOR_MINOR_MINOR}" -ge 4 ]]; then # We support 6.x, and 5.x from 5.4
			declare -g KERNEL_HAS_WORKING_HEADERS="yes"
			declare -g KERNEL_MAJOR="${KERNEL_MAJOR_MINOR_MAJOR}"
		elif [[ "${KERNEL_MAJOR_MINOR_MAJOR}" -eq 4 && "${KERNEL_MAJOR_MINOR_MINOR}" -ge 19 ]]; then
			declare -g KERNEL_MAJOR=4                              # We support 4.19+ (less than 5.0) is supported, and headers via full source
			declare -g KERNEL_HAS_WORKING_HEADERS_FULL_SOURCE="no" # full-source based headers. experimental. set to yes here to enable
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
		declare -g ARMBIAN_WILL_BUILD_KERNEL=no
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
		exit_with_error "Distribution ${distribution_name} does not exist"
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
