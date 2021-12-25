function prepare_and_config_main_build_single() {
	# default umask for root is 022 so parent directories won't be group writeable without this
	# this is used instead of making the chmod in prepare_host() recursive
	umask 002

	# destination. # @TODO: logging this is when we can start logging to file. make sure.
	if [ -d "$CONFIG_PATH/output" ]; then
		DEST="${CONFIG_PATH}"/output
	else
		DEST="${SRC}"/output
	fi
	display_alert "Determined DEST:" "${DEST}" "debug"

	interactive_config_prepare_terminal

	# Warnings mitigation
	[[ -z $LANGUAGE ]] && export LANGUAGE="en_US:en"      # set to english if not set
	[[ -z $CONSOLE_CHAR ]] && export CONSOLE_CHAR="UTF-8" # set console to UTF-8 if not set

	# set log path
	LOG_SUBPATH=${LOG_SUBPATH:=debug}
	mkdir -p "${DEST}/${LOG_SUBPATH}" # This creates the logging output.

	# compress and remove old logs, if they exist.
	if [[ -f "${DEST}/${LOG_SUBPATH}/timestamp" ]]; then
		if ls "${DEST}/${LOG_SUBPATH}/"*.log &> /dev/null; then
			display_alert "Archiving previous build logs..." "${DEST}/${LOG_SUBPATH}" "info"
			(cd "${DEST}/${LOG_SUBPATH}" && tar -czf logs-"$(< timestamp)".tgz ./*.log) # > /dev/null 2>&1
			rm -f "${DEST}/${LOG_SUBPATH}"/*.log
		fi
		# delete compressed logs older than 7 days
		find "${DEST}"/${LOG_SUBPATH} -name '*.tgz' -mtime +7 -delete
	fi

	# Mark a timestamp, for next build.
	date +"%d_%m_%Y-%H_%M_%S" > "${DEST}"/${LOG_SUBPATH}/timestamp

	# PROGRESS_LOG_TO_FILE is either yes, or unset. (@TODO: this is still used in buildpkg)
	if [[ $PROGRESS_LOG_TO_FILE != yes ]]; then unset PROGRESS_LOG_TO_FILE; fi

	SHOW_WARNING=yes

	display_alert "Starting single build process" "${BOARD}" "info"

	# @TODO: rpardini: ccache belongs in compilation, not config. I think.
	if [[ $USE_CCACHE != no ]]; then
		CCACHE=ccache
		export PATH="/usr/lib/ccache:$PATH"
		# private ccache directory to avoid permission issues when using build script with "sudo"
		# see https://ccache.samba.org/manual.html#_sharing_a_cache for alternative solution
		[[ $PRIVATE_CCACHE == yes ]] && export CCACHE_DIR=$SRC/cache/ccache
	else
		CCACHE=""
	fi

	# @TODO: rpardini: refactor this into 'repo' stuff. Out of configuration, I think.
	if [[ -n $REPOSITORY_UPDATE ]]; then
		# select stable/beta configuration
		if [[ $BETA == yes ]]; then
			DEB_STORAGE=$DEST/debs-beta
			REPO_STORAGE=$DEST/repository-beta
			REPO_CONFIG="aptly-beta.conf"
		else
			DEB_STORAGE=$DEST/debs
			REPO_STORAGE=$DEST/repository
			REPO_CONFIG="aptly.conf"
		fi

		# For user override
		if [[ -f "${USERPATCHES_PATH}"/lib.config ]]; then
			display_alert "Using user configuration override" "userpatches/lib.config" "info"
			source "${USERPATCHES_PATH}"/lib.config
		fi

		repo-manipulate "$REPOSITORY_UPDATE"
		exit
	fi

	interactive_config_ask_kernel
	[[ -z $KERNEL_ONLY ]] && exit_with_error "No option selected: KERNEL_ONLY"
	[[ -z $KERNEL_CONFIGURE ]] && exit_with_error "No option selected: KERNEL_CONFIGURE"

	interactive_config_ask_board_list
	[[ -z $BOARD ]] && exit_with_error "No board selected: BOARD"

	if [[ -f $SRC/config/boards/${BOARD}.conf ]]; then
		BOARD_TYPE='conf'
	elif [[ -f $SRC/config/boards/${BOARD}.csc ]]; then
		BOARD_TYPE='csc'
	elif [[ -f $SRC/config/boards/${BOARD}.wip ]]; then
		BOARD_TYPE='wip'
	elif [[ -f $SRC/config/boards/${BOARD}.eos ]]; then
		BOARD_TYPE='eos'
	elif [[ -f $SRC/config/boards/${BOARD}.tvb ]]; then
		BOARD_TYPE='tvb'
	fi

	# @TODO: rpardini: this is when Alice enters the hole. Sourcing stuff, extensions getting activated, etc.

	display_alert "Sourcing board configuration" "${BOARD}.${BOARD_TYPE}" "info"
	# shellcheck source=/dev/null
	source "${SRC}/config/boards/${BOARD}.${BOARD_TYPE}"
	LINUXFAMILY="${BOARDFAMILY}"

	# @TODO: interesting. this sourced the board config. What sources the family?


	[[ -z $KERNEL_TARGET ]] && exit_with_error "Board configuration does not define valid kernel config"

	interactive_config_ask_branch
	[[ -z $BRANCH ]] && exit_with_error "No kernel branch selected: BRANCH"
	[[ $KERNEL_TARGET != *$BRANCH* ]] && exit_with_error "Kernel branch not defined for this board" "$BRANCH"

	interactive_config_ask_release
	[[ -z $RELEASE ]] && exit_with_error "No release selected: RELEASE"

	interactive_config_ask_desktop_build

	interactive_config_ask_standard_or_minimal

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

	do_main_configuration

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

	if [[ $BETA == yes ]]; then
		IMAGE_TYPE=nightly
	elif [[ $BETA != "yes" && $BUILD_ALL == yes && -n $GPG_PASS ]]; then
		IMAGE_TYPE=stable
	else
		IMAGE_TYPE=user-built
	fi

	export BOOTSOURCEDIR="${BOOTDIR}/$(branch2dir "${BOOTBRANCH}")"
	export LINUXSOURCEDIR="${KERNELDIR}/$(branch2dir "${KERNELBRANCH}")"
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
