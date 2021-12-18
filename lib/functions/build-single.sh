# Some utility functions
branch2dir() {
	[[ "${1}" == "head" ]] && echo "HEAD" || echo "${1##*:}"
}

cleanup_list() {
	local varname="${1}"
	local list_to_clean="${!varname}"
	list_to_clean="${list_to_clean#"${list_to_clean%%[![:space:]]*}"}"
	list_to_clean="${list_to_clean%"${list_to_clean##*[![:space:]]}"}"
	echo ${list_to_clean}
}

# This does NOT run under the logging manager. We should invoke the do_with_logging wrapper for
# strategic parts of this. Attention: build_rootfs_image does it's own logging, so just let that be.
main_default_build_single() {
	start=$(date +%s)
	# Check and install dependencies, directory structure and settings
	# The OFFLINE_WORK variable inside the function
	LOG_SECTION="prepare_host" do_with_logging prepare_host

	if [[ "${JUST_INIT}" == "yes" ]]; then
		exit 0
	fi

	if [[ $CLEAN_LEVEL == *sources* ]]; then
		cleaning "sources"
	fi
	# ignore updates help on building all images - for internal purposes
	if [[ $IGNORE_UPDATES != yes ]]; then
		LOG_SECTION="fetch_sources_kernel_uboot_atf" do_with_logging fetch_sources_kernel_uboot_atf
		LOG_SECTION="fetch_and_build_host_tools" do_with_logging fetch_and_build_host_tools

		for option in $(tr ',' ' ' <<< "$CLEAN_LEVEL"); do
			if [[ $option != sources ]]; then
				LOG_SECTION="cleaning" do_with_logging cleaning "$option"
			fi
		done
	fi

	# Don't build u-boot at all if the BOOTCONFIG is 'none'.
	if [[ "${BOOTCONFIG}" != "none" ]]; then
		# @TODO: refactor this. we use it very often
		# Compile u-boot if packed .deb does not exist or use the one from repository
		if [[ ! -f "${DEB_STORAGE}"/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb ]]; then
			if [[ -n "${ATFSOURCE}" && "${REPOSITORY_INSTALL}" != *u-boot* ]]; then
				LOG_SECTION="compile_atf" do_with_logging compile_atf
			fi
			# @TODO: refactor this construct. we use it too many times.
			if [[ "${REPOSITORY_INSTALL}" != *u-boot* ]]; then
				LOG_SECTION="compile_uboot" do_with_logging compile_uboot
			fi
		fi
	fi

	# Compile kernel if packed .deb does not exist or use the one from repository
	if [[ ! -f ${DEB_STORAGE}/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb ]]; then
		export KDEB_CHANGELOG_DIST=$RELEASE
		if [[ -n $KERNELSOURCE ]] && [[ "${REPOSITORY_INSTALL}" != *kernel* ]]; then
			LOG_SECTION="compile_kernel" do_with_logging compile_kernel
		fi
	fi

	# Compile armbian-config if packed .deb does not exist or use the one from repository
	if [[ ! -f ${DEB_STORAGE}/armbian-config_${REVISION}_all.deb ]]; then
		if [[ "${REPOSITORY_INSTALL}" != *armbian-config* ]]; then
			LOG_SECTION="compile_armbian-config" do_with_logging compile_armbian-config
		fi
	fi

	# Compile armbian-zsh if packed .deb does not exist or use the one from repository
	if [[ ! -f ${DEB_STORAGE}/armbian-zsh_${REVISION}_all.deb ]]; then
		if [[ "${REPOSITORY_INSTALL}" != *armbian-zsh* ]]; then
			LOG_SECTION="compile_armbian-zsh" do_with_logging compile_armbian-zsh
		fi
	fi

	# Compile armbian-firmware if packed .deb does not exist or use the one from repository
	if ! ls "${DEB_STORAGE}/armbian-firmware_${REVISION}_all.deb" 1> /dev/null 2>&1 || ! ls "${DEB_STORAGE}/armbian-firmware-full_${REVISION}_all.deb" 1> /dev/null 2>&1; then

		if [[ "${REPOSITORY_INSTALL}" != *armbian-firmware* ]]; then
			if [[ "${INSTALL_ARMBIAN_FIRMWARE:-yes}" == "yes" ]]; then # Build firmware by default.
				# Build the light version of firmware package
				FULL="" REPLACE="-full" LOG_SECTION="compile_firmware" do_with_logging compile_firmware

				# Build the full version of firmware package
				FULL="-full" REPLACE="" LOG_SECTION="compile_firmware" do_with_logging compile_firmware

			fi
		fi
	fi

	overlayfs_wrapper "cleanup"

	# create board support package
	if [[ -n $RELEASE && ! -f ${DEB_STORAGE}/$RELEASE/${BSP_CLI_PACKAGE_FULLNAME}.deb ]]; then
		LOG_SECTION="create_board_package" do_with_logging create_board_package
	fi

	# create desktop package
	if [[ -n $RELEASE && $DESKTOP_ENVIRONMENT && ! -f ${DEB_STORAGE}/$RELEASE/${CHOSEN_DESKTOP}_${REVISION}_all.deb ]]; then
		LOG_SECTION="create_desktop_package" do_with_logging create_desktop_package
	fi
	if [[ -n $RELEASE && $DESKTOP_ENVIRONMENT && ! -f ${DEB_STORAGE}/${RELEASE}/${BSP_DESKTOP_PACKAGE_FULLNAME}.deb ]]; then
		LOG_SECTION="create_bsp_desktop_package" do_with_logging create_bsp_desktop_package
	fi

	# build additional packages
	if [[ $EXTERNAL_NEW == compile ]]; then
		LOG_SECTION="chroot_build_packages" do_with_logging chroot_build_packages
	fi

	# end of kernel-only, so display what was built.
	if [[ $KERNEL_ONLY != yes ]]; then
		display_alert "Kernel build done" "@host" "target-reached"
		display_alert "Target directory" "${DEB_STORAGE}/" "info"
		display_alert "File name" "${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb" "info"
	fi

	# build rootfs, if not only kernel.
	if [[ $KERNEL_ONLY != yes ]]; then
		display_alert "Building image" "${BOARD}" "target-started"
		[[ $BSP_BUILD != yes ]] && build_rootfs_image # old debootstrap-ng. !!!LOGGING!!! handled inside, there are many sub-parts.
		display_alert "Done building image" "${BOARD}" "target-reached"
	fi

	call_extension_method "run_after_build" << 'RUN_AFTER_BUILD'
*hook for function to run after build, i.e. to change owner of `$SRC`*
Really one of the last hooks ever called. The build has ended. Congratulations.
- *NOTE:* this will run only if there were no errors during build process.
RUN_AFTER_BUILD

	end=$(date +%s)
	runtime=$(((end - start) / 60))
	display_alert "Runtime" "$runtime min" "info"

	[ "$(systemd-detect-virt)" == 'docker' ] && BUILD_CONFIG='docker'

	# Make it easy to repeat build by displaying build options used. Prepare array.
	local -a repeat_args=("./compile.sh" "${BUILD_CONFIG}" " BRANCH=${BRANCH}")
	[[ -n ${RELEASE} ]] && repeat_args+=("RELEASE=${RELEASE}")
	[[ -n ${BUILD_MINIMAL} ]] && repeat_args+=("BUILD_MINIMAL=${BUILD_MINIMAL}")
	[[ -n ${BUILD_DESKTOP} ]] && repeat_args+=("BUILD_DESKTOP=${BUILD_DESKTOP}")
	[[ -n ${KERNEL_ONLY} ]] && repeat_args+=("KERNEL_ONLY=${KERNEL_ONLY}")
	[[ -n ${KERNEL_CONFIGURE} ]] && repeat_args+=("KERNEL_CONFIGURE=${KERNEL_CONFIGURE}")
	[[ -n ${DESKTOP_ENVIRONMENT} ]] && repeat_args+=("DESKTOP_ENVIRONMENT=${DESKTOP_ENVIRONMENT}")
	[[ -n ${DESKTOP_ENVIRONMENT_CONFIG_NAME} ]] && repeat_args+=("DESKTOP_ENVIRONMENT_CONFIG_NAME=${DESKTOP_ENVIRONMENT_CONFIG_NAME}")
	[[ -n ${DESKTOP_APPGROUPS_SELECTED} ]] && repeat_args+=("DESKTOP_APPGROUPS_SELECTED=\"${DESKTOP_APPGROUPS_SELECTED}\"")
	[[ -n ${DESKTOP_APT_FLAGS_SELECTED} ]] && repeat_args+=("DESKTOP_APT_FLAGS_SELECTED=\"${DESKTOP_APT_FLAGS_SELECTED}\"")
	[[ -n ${COMPRESS_OUTPUTIMAGE} ]] && repeat_args+=("COMPRESS_OUTPUTIMAGE=${COMPRESS_OUTPUTIMAGE}")
	display_alert "Repeat Build Options" "${repeat_args[*]}" "ext" # * = expand array, space delimited, single-word.

}

function fetch_sources_kernel_uboot_atf() {
	if [[ -n $BOOTSOURCE ]]; then
		display_alert "Downloading sources" "u-boot" "git"
		fetch_from_repo "$BOOTSOURCE" "$BOOTDIR" "$BOOTBRANCH" "yes" # fetch_from_repo <url> <dir> <ref> <subdir_flag>
	fi

	if [[ -n $KERNELSOURCE ]]; then
		display_alert "Downloading sources" "kernel" "git"
		fetch_from_repo "$KERNELSOURCE" "$KERNELDIR" "$KERNELBRANCH" "yes"
	fi

	if [[ -n $ATFSOURCE ]]; then
		display_alert "Downloading sources" "atf" "git"
		fetch_from_repo "$ATFSOURCE" "$ATFDIR" "$ATFBRANCH" "yes"
	fi
}

function fetch_and_build_host_tools() {
	call_extension_method "fetch_sources_tools" <<- 'FETCH_SOURCES_TOOLS'
		*fetch host-side sources needed for tools and build*
		Run early to fetch_from_repo or otherwise obtain sources for needed tools.
	FETCH_SOURCES_TOOLS

	call_extension_method "build_host_tools" <<- 'BUILD_HOST_TOOLS'
		*build needed tools for the build, host-side*
		After sources are fetched, build host-side tools needed for the build.
	BUILD_HOST_TOOLS

}

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

	if [[ $BUILD_ALL != "yes" && -z $ROOT_FS_CREATE_ONLY ]]; then
		if [[ -t 1 ]]; then # "-t fd return True if file descriptor fd is open and refers to a terminal"
			# override stty size, if stdin is a terminal.
			[[ -n $COLUMNS ]] && stty cols $COLUMNS
			[[ -n $LINES ]] && stty rows $LINES
			TTY_X=$(($(stty size | awk '{print $2}') - 6)) # determine terminal width
			TTY_Y=$(($(stty size | awk '{print $1}') - 6)) # determine terminal height
		fi
	fi

	# We'll use this title on all menus
	backtitle="Armbian building script, https://www.armbian.com | https://docs.armbian.com | (c) 2013-2021 Igor Pecovnik "

	# Warnings mitigation
	[[ -z $LANGUAGE ]] && export LANGUAGE="en_US:en"      # set to english if not set
	[[ -z $CONSOLE_CHAR ]] && export CONSOLE_CHAR="UTF-8" # set console to UTF-8 if not set

	# set log path
	LOG_SUBPATH=${LOG_SUBPATH:=debug}

	# compress and remove old logs # @TODO: logging, this is essential...
	mkdir -p "${DEST}"/${LOG_SUBPATH}
	(cd "${DEST}"/${LOG_SUBPATH} && tar -czf logs-"$(< timestamp)".tgz ./*.log) > /dev/null 2>&1
	rm -f "${DEST}"/${LOG_SUBPATH}/*.log > /dev/null 2>&1
	date +"%d_%m_%Y-%H_%M_%S" > "${DEST}"/${LOG_SUBPATH}/timestamp

	# delete compressed logs older than 7 days
	(cd "${DEST}"/${LOG_SUBPATH} && find . -name '*.tgz' -mtime +7 -delete) > /dev/null

	if [[ $PROGRESS_DISPLAY == none ]]; then
		display_alert "Output will be silenced." "PROGRESS_DISPLAY=none" "warning"
		export OUTPUT_VERYSILENT=yes
	elif [[ $PROGRESS_DISPLAY == dialog ]]; then # @TODO: WHO SETS THIS?? this is key to solving the logging cray-cray
		export OUTPUT_DIALOG=yes
	fi

	# PROGRESS_LOG_TO_FILE is either yes, or unset.
	if [[ $PROGRESS_LOG_TO_FILE != yes ]]; then unset PROGRESS_LOG_TO_FILE; fi

	SHOW_WARNING=yes

	if [[ $USE_CCACHE != no ]]; then
		CCACHE=ccache
		export PATH="/usr/lib/ccache:$PATH"
		# private ccache directory to avoid permission issues when using build script with "sudo"
		# see https://ccache.samba.org/manual.html#_sharing_a_cache for alternative solution
		[[ $PRIVATE_CCACHE == yes ]] && export CCACHE_DIR=$SRC/cache/ccache
	else
		CCACHE=""
	fi

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

	# if KERNEL_ONLY, KERNEL_CONFIGURE, BOARD, BRANCH or RELEASE are not set, display selection menu
	if [[ -z $KERNEL_ONLY ]]; then
		options+=("yes" "U-boot and kernel packages")
		options+=("no" "Full OS image for flashing")
		KERNEL_ONLY=$(dialog --stdout --title "Choose an option" --backtitle "$backtitle" --no-tags \
			--menu "Select what to build" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		unset options
		[[ -z $KERNEL_ONLY ]] && exit_with_error "No option selected"
	fi

	if [[ -z $KERNEL_CONFIGURE ]]; then
		options+=("no" "Do not change the kernel configuration")
		options+=("yes" "Show a kernel configuration menu before compilation")
		options+=("prebuilt" "Use precompiled packages from Armbian repository")
		KERNEL_CONFIGURE=$(dialog --stdout --title "Choose an option" --backtitle "$backtitle" --no-tags \
			--menu "Select the kernel configuration" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		unset options
		[[ -z $KERNEL_CONFIGURE ]] && exit_with_error "No option selected"
	fi

	if [[ -z $BOARD ]]; then
		WIP_STATE=supported
		WIP_BUTTON='CSC/WIP/EOS/TVB'
		STATE_DESCRIPTION=' - boards with high level of software maturity'
		temp_rc=$(mktemp)

		while true; do
			options=()
			if [[ $WIP_STATE == supported ]]; then
				for board in "${SRC}"/config/boards/*.conf; do
					options+=("$(basename "${board}" | cut -d'.' -f1)" "$(head -1 "${board}" | cut -d'#' -f2)")
				done
			else
				for board in "${SRC}"/config/boards/*.wip; do
					options+=("$(basename "${board}" | cut -d'.' -f1)" "\Z1(WIP)\Zn $(head -1 "${board}" | cut -d'#' -f2)")
				done
				for board in "${SRC}"/config/boards/*.csc; do
					options+=("$(basename "${board}" | cut -d'.' -f1)" "\Z1(CSC)\Zn $(head -1 "${board}" | cut -d'#' -f2)")
				done
				for board in "${SRC}"/config/boards/*.eos; do
					options+=("$(basename "${board}" | cut -d'.' -f1)" "\Z1(EOS)\Zn $(head -1 "${board}" | cut -d'#' -f2)")
				done
				for board in "${SRC}"/config/boards/*.tvb; do
					options+=("$(basename "${board}" | cut -d'.' -f1)" "\Z1(TVB)\Zn $(head -1 "${board}" | cut -d'#' -f2)")
				done
			fi

			if [[ $WIP_STATE != supported ]]; then
				cat <<- 'EOF' > "${temp_rc}"
					dialog_color = (RED,WHITE,OFF)
					screen_color = (WHITE,RED,ON)
					tag_color = (RED,WHITE,ON)
					item_selected_color = (WHITE,RED,ON)
					tag_selected_color = (WHITE,RED,ON)
					tag_key_selected_color = (WHITE,RED,ON)
				EOF
			else
				echo > "${temp_rc}"
			fi
			BOARD=$(DIALOGRC=$temp_rc dialog --stdout --title "Choose a board" --backtitle "$backtitle" --scrollbar \
				--colors --extra-label "Show $WIP_BUTTON" --extra-button \
				--menu "Select the target board. Displaying:\n$STATE_DESCRIPTION" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
			STATUS=$?
			if [[ $STATUS == 3 ]]; then
				if [[ $WIP_STATE == supported ]]; then
					[[ $SHOW_WARNING == yes ]] && show_developer_warning
					STATE_DESCRIPTION=' - \Z1(CSC)\Zn - Community Supported Configuration\n - \Z1(WIP)\Zn - Work In Progress
				\n - \Z1(EOS)\Zn - End Of Support\n - \Z1(TVB)\Zn - TV boxes'
					WIP_STATE=unsupported
					WIP_BUTTON='matured'
					EXPERT=yes
				else
					STATE_DESCRIPTION=' - boards with high level of software maturity'
					WIP_STATE=supported
					WIP_BUTTON='CSC/WIP/EOS'
					EXPERT=no
				fi
				continue
			elif [[ $STATUS == 0 ]]; then
				break
			fi
			unset options
			[[ -z $BOARD ]] && exit_with_error "No board selected"
		done
	fi

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

	# shellcheck source=/dev/null
	source "${SRC}/config/boards/${BOARD}.${BOARD_TYPE}"
	LINUXFAMILY="${BOARDFAMILY}"

	[[ -z $KERNEL_TARGET ]] && exit_with_error "Board configuration does not define valid kernel config"

	if [[ -z $BRANCH ]]; then
		options=()
		[[ $KERNEL_TARGET == *current* ]] && options+=("current" "Recommended. Come with best support")
		[[ $KERNEL_TARGET == *legacy* ]] && options+=("legacy" "Old stable / Legacy")
		[[ $KERNEL_TARGET == *edge* && $EXPERT = yes ]] && options+=("edge" "\Z1Bleeding edge from @kernel.org\Zn")

		# do not display selection dialog if only one kernel branch is available
		if [[ "${#options[@]}" == 2 ]]; then
			BRANCH="${options[0]}"
		else
			BRANCH=$(dialog --stdout --title "Choose a kernel" --backtitle "$backtitle" --colors \
				--menu "Select the target kernel branch\nExact kernel versions depend on selected board" \
				$TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		fi
		unset options
		[[ -z $BRANCH ]] && exit_with_error "No kernel branch selected"
		[[ $BRANCH == dev && $SHOW_WARNING == yes ]] && show_developer_warning
	else
		[[ $BRANCH == next ]] && KERNEL_TARGET="next"
		# next = new legacy. Should stay for backward compatibility, but be removed from menu above
		# or we left definitions in board configs and only remove menu
		[[ $KERNEL_TARGET != *$BRANCH* ]] && exit_with_error "Kernel branch not defined for this board" "$BRANCH"
	fi

	if [[ $KERNEL_ONLY != yes && -z $RELEASE ]]; then
		options=()
		distros_options
		RELEASE=$(dialog --stdout --title "Choose a release package base" --backtitle "$backtitle" \
			--menu "Select the target OS release package base" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		echo "options : ${options}"
		[[ -z $RELEASE ]] && exit_with_error "No release selected"
		unset options
	fi

	# don't show desktop option if we choose minimal build
	[[ $BUILD_MINIMAL == yes ]] && BUILD_DESKTOP=no

	if [[ $KERNEL_ONLY != yes && -z $BUILD_DESKTOP ]]; then
		# read distribution support status which is written to the armbian-release file
		set_distribution_status
		options=()
		options+=("no" "Image with console interface (server)")
		options+=("yes" "Image with desktop environment")
		BUILD_DESKTOP=$(dialog --stdout --title "Choose image type" --backtitle "$backtitle" --no-tags \
			--menu "Select the target image type" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		unset options
		[[ -z $BUILD_DESKTOP ]] && exit_with_error "No option selected"
		if [[ ${BUILD_DESKTOP} == "yes" ]]; then
			BUILD_MINIMAL=no
			SELECTED_CONFIGURATION="desktop"
		fi
	fi

	if [[ $KERNEL_ONLY != yes && $BUILD_DESKTOP == no && -z $BUILD_MINIMAL ]]; then
		options=()
		options+=("no" "Standard image with console interface")
		options+=("yes" "Minimal image with console interface")
		BUILD_MINIMAL=$(dialog --stdout --title "Choose image type" --backtitle "$backtitle" --no-tags \
			--menu "Select the target image type" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		unset options
		[[ -z $BUILD_MINIMAL ]] && exit_with_error "No option selected"
		if [[ $BUILD_MINIMAL == "yes" ]]; then
			SELECTED_CONFIGURATION="cli_minimal"
		else
			SELECTED_CONFIGURATION="cli_standard"
		fi
	fi

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
		REPOSITORY_INSTALL="u-boot,kernel,bsp,armbian-zsh,armbian-config,armbian-firmware${BUILD_DESKTOP:+,armbian-desktop}"

	do_main_configuration

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

	BOOTSOURCEDIR="${BOOTDIR}/$(branch2dir "${BOOTBRANCH}")"
	LINUXSOURCEDIR="${KERNELDIR}/$(branch2dir "${KERNELBRANCH}")"
	[[ -n $ATFSOURCE ]] && ATFSOURCEDIR="${ATFDIR}/$(branch2dir "${ATFBRANCH}")"

	BSP_CLI_PACKAGE_NAME="armbian-bsp-cli-${BOARD}${EXTRA_BSP_NAME}"
	BSP_CLI_PACKAGE_FULLNAME="${BSP_CLI_PACKAGE_NAME}_${REVISION}_${ARCH}"
	BSP_DESKTOP_PACKAGE_NAME="armbian-bsp-desktop-${BOARD}${EXTRA_BSP_NAME}"
	BSP_DESKTOP_PACKAGE_FULLNAME="${BSP_DESKTOP_PACKAGE_NAME}_${REVISION}_${ARCH}"

	CHOSEN_UBOOT=linux-u-boot-${BRANCH}-${BOARD}
	CHOSEN_KERNEL=linux-image-${BRANCH}-${LINUXFAMILY}
	CHOSEN_ROOTFS=${BSP_CLI_PACKAGE_NAME}
	CHOSEN_DESKTOP=armbian-${RELEASE}-desktop-${DESKTOP_ENVIRONMENT}
	CHOSEN_KSRC=linux-source-${BRANCH}-${LINUXFAMILY}
}
