#!/usr/bin/env bash

function prepare_and_config_main_build_single() {
	# default umask for root is 022 so parent directories won't be group writeable without this
	# this is used instead of making the chmod in prepare_host() recursive
	umask 002

	interactive_config_prepare_terminal

	# Warnings mitigation
	[[ -z $LANGUAGE ]] && export LANGUAGE="en_US:en"      # set to english if not set
	[[ -z $CONSOLE_CHAR ]] && export CONSOLE_CHAR="UTF-8" # set console to UTF-8 if not set

	export SHOW_WARNING=yes # If you try something that requires EXPERT=yes.

	display_alert "Starting single build process" "${BOARD}" "info"

	# @TODO: rpardini: ccache belongs in compilation, not config. I think.
	if [[ $USE_CCACHE != no ]]; then
		CCACHE=ccache
		export PATH="/usr/lib/ccache:$PATH"
		# private ccache directory to avoid permission issues when using build script with "sudo"
		# see https://ccache.samba.org/manual.html#_sharing_a_cache for alternative solution
		[[ $PRIVATE_CCACHE == yes ]] && export CCACHE_DIR=$SRC/cache/ccache
		# Done elsewhere in a-n # # Check if /tmp is mounted as tmpfs make a temporary ccache folder there for faster operation.
		# Done elsewhere in a-n # if [ "$(findmnt --noheadings --output FSTYPE --target "/tmp" --uniq)" == "tmpfs" ]; then
		# Done elsewhere in a-n # 	export CCACHE_TEMPDIR="/tmp/ccache-tmp"
		# Done elsewhere in a-n # fi

	else
		CCACHE=""
	fi

	# if KERNEL_ONLY, KERNEL_CONFIGURE, BOARD, BRANCH or RELEASE are not set, display selection menu

	backward_compatibility_build_only

	interactive_config_ask_kernel
	[[ -z $KERNEL_ONLY ]] && exit_with_error "No option selected: KERNEL_ONLY"
	[[ -z $KERNEL_CONFIGURE ]] && exit_with_error "No option selected: KERNEL_CONFIGURE"

	interactive_config_ask_board_list # this uses get_list_of_all_buildable_boards too
	[[ -z $BOARD ]] && exit_with_error "No board selected: BOARD"

	declare -a arr_all_board_names=()                                                                           # arrays
	declare -A dict_all_board_types=() dict_all_board_source_files=()                                           # dictionaries
	get_list_of_all_buildable_boards arr_all_board_names "" dict_all_board_types dict_all_board_source_files "" # invoke

	BOARD_TYPE="${dict_all_board_types["${BOARD}"]}"
	BOARD_SOURCE_FILES="${dict_all_board_source_files["${BOARD}"]}"

	for BOARD_SOURCE_FILE in ${BOARD_SOURCE_FILES}; do # No quotes, so expand the space-delimited list
		display_alert "Sourcing board configuration" "${BOARD_SOURCE_FILE}" "info"
		# shellcheck source=/dev/null
		source "${BOARD_SOURCE_FILE}"
	done

	LINUXFAMILY="${BOARDFAMILY}" # @TODO: wtf? why? this is (100%?) rewritten by family config!
	# this sourced the board config. do_main_configuration will source the family file.

	[[ -z $KERNEL_TARGET ]] && exit_with_error "Board configuration does not define valid kernel config"

	interactive_config_ask_branch
	[[ -z $BRANCH ]] && exit_with_error "No kernel branch selected: BRANCH"
	[[ $KERNEL_TARGET != *$BRANCH* ]] && display_alert "Kernel branch not defined for this board" "$BRANCH for ${BOARD}" "warn"

	build_task_is_enabled "bootstrap" && {

		interactive_config_ask_release
		[[ -z $RELEASE && ${KERNEL_ONLY} != yes ]] && exit_with_error "No release selected: RELEASE"

		interactive_config_ask_desktop_build

		interactive_config_ask_standard_or_minimal
	}

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

	do_main_configuration # This initializes the extension manager among a lot of other things, and call extension_prepare_config() hook

	# @TODO: this does not belong in configuration. it's a compilation thing. move there
	# optimize build time with 100% CPU usage
	CPUS=$(grep -c 'processor' /proc/cpuinfo)
	if [[ $USEALLCORES != no ]]; then
		CTHREADS="-j$((CPUS + CPUS / 2))"
	else
		CTHREADS="-j1"
	fi

	call_extension_method "post_determine_cthreads" "config_post_determine_cthreads" <<- 'POST_DETERMINE_CTHREADS'
		*give config a chance modify CTHREADS programatically. A build server may work better with hyperthreads-1 for example.*
		Called early, before any compilation work starts.
	POST_DETERMINE_CTHREADS

	if [[ "$BETA" == "yes" ]]; then
		IMAGE_TYPE=nightly
	elif [ "$BETA" == "no" ] || [ "$RC" == "yes" ]; then
		IMAGE_TYPE=stable
	else
		IMAGE_TYPE=user-built
	fi

	export BOOTSOURCEDIR="${BOOTDIR}/$(branch2dir "${BOOTBRANCH}")"
	[[ -n $ATFSOURCE ]] && export ATFSOURCEDIR="${ATFDIR}/$(branch2dir "${ATFBRANCH}")"

	export BSP_CLI_PACKAGE_NAME="armbian-bsp-cli-${BOARD}${EXTRA_BSP_NAME}"
	export BSP_CLI_PACKAGE_FULLNAME="${BSP_CLI_PACKAGE_NAME}_${REVISION}_${ARCH}"
	export BSP_DESKTOP_PACKAGE_NAME="armbian-bsp-desktop-${BOARD}${EXTRA_BSP_NAME}"
	export BSP_DESKTOP_PACKAGE_FULLNAME="${BSP_DESKTOP_PACKAGE_NAME}_${REVISION}_${ARCH}"

	export CHOSEN_UBOOT=linux-u-boot-${BRANCH}-${BOARD}
	export CHOSEN_KERNEL=linux-image-${BRANCH}-${LINUXFAMILY}
	export CHOSEN_ROOTFS=${BSP_CLI_PACKAGE_NAME}
	export CHOSEN_DESKTOP=armbian-${RELEASE}-desktop-${DESKTOP_ENVIRONMENT}
	export CHOSEN_KSRC=linux-source-${BRANCH}-${LINUXFAMILY}

	# So for kernel full cached rebuilds.
	# We wanna be able to rebuild kernels very fast. so it only makes sense to use a dir for each built kernel.
	# That is the "default" layout; there will be as many source dirs as there are built kernel debs.
	# But, it really makes much more sense if the major.minor (such as 5.10, 5.15, or 4.4) of kernel has its own
	# tree. So in the end:
	# <arch>-<major.minor>[-<family>]
	# So we gotta explictly know the major.minor to be able to do that scheme.
	# If we don't know, we could use BRANCH as reference, but that changes over time, and leads to wastage.
	if [[ -n "${KERNELSOURCE}" ]]; then
		export ARMBIAN_WILL_BUILD_KERNEL="${CHOSEN_KERNEL}-${ARCH}"
		if [[ "x${KERNEL_MAJOR_MINOR}x" == "xx" ]]; then
			exit_with_error "BAD config, missing" "KERNEL_MAJOR_MINOR" "err"
		fi
		export KERNEL_HAS_WORKING_HEADERS="no" # assume the worst, and all surprises will be happy ones
		# Parse/validate the the major, bail if no match
		if linux-version compare "${KERNEL_MAJOR_MINOR}" ge "5.4"; then # We support 5.x from 5.4
			export KERNEL_HAS_WORKING_HEADERS="yes"                        # We can build working headers for 5.x even when cross compiling.
			export KERNEL_MAJOR=5
			export KERNEL_MAJOR_SHALLOW_TAG="v${KERNEL_MAJOR_MINOR}-rc1"
		elif linux-version compare "${KERNEL_MAJOR_MINOR}" ge "4.4" && linux-version compare "${KERNEL_MAJOR_MINOR}" lt "5.0"; then
			export KERNEL_MAJOR=4 # We support 4.x from 4.4
			export KERNEL_MAJOR_SHALLOW_TAG="v${KERNEL_MAJOR_MINOR}-rc1"
		else
			# If you think you can patch packaging to support this, you're probably right. Is _worth_ it though?
			exit_with_error "Kernel series unsupported" "'${KERNEL_MAJOR_MINOR}' is unsupported, or bad config"
		fi

		export LINUXSOURCEDIR="kernel/${ARCH}__${KERNEL_MAJOR_MINOR}__${LINUXFAMILY}"
	else
		export KERNEL_HAS_WORKING_HEADERS="yes" # I assume non-Armbian kernels have working headers, eg: Debian/Ubuntu generic do.
		export ARMBIAN_WILL_BUILD_KERNEL=no
	fi

	if [[ -n "${BOOTCONFIG}" ]] && [[ "${BOOTCONFIG}" != "none" ]]; then
		export ARMBIAN_WILL_BUILD_UBOOT=yes
	else
		export ARMBIAN_WILL_BUILD_UBOOT=no
	fi

	display_alert "Extensions: finish configuration" "extension_finish_config" "debug"
	call_extension_method "extension_finish_config" <<- 'EXTENSION_FINISH_CONFIG'
		*allow extensions a last chance at configuration just before it is done*
		After kernel versions are set, package names determined, etc.
		This runs *late*, and is the final step before finishing configuration.
		Don't change anything not coming from other variables or meant to be configured by the user.
	EXTENSION_FINISH_CONFIG

	display_alert "Done with prepare_and_config_main_build_single" "${BOARD}.${BOARD_TYPE}" "info"
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

	return 0 # due to last stmt above being a shortcut conditional
}

# Some utility functions
branch2dir() {
	[[ "${1}" == "head" ]] && echo "HEAD" || echo "${1##*:}"
}
