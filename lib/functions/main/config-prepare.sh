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
		if [[ -t 0 ]]; then # "-t fd return True if file descriptor fd is open and refers to a terminal". 0 = stdin, 1 = stdout, 2 = stderr, 3+ custom
			display_alert "stdin is a terminal" "or is it?" "warning"
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

	if [[ $PROGRESS_DISPLAY == none ]]; then
		display_alert "Output will be silenced." "PROGRESS_DISPLAY=none" "warning"
		export OUTPUT_VERYSILENT=yes
	elif [[ $PROGRESS_DISPLAY == dialog ]]; then # @TODO: WHO SETS THIS?? this is key to solving the logging cray-cray
		export OUTPUT_DIALOG=yes
	fi

	# PROGRESS_LOG_TO_FILE is either yes, or unset.
	if [[ $PROGRESS_LOG_TO_FILE != yes ]]; then unset PROGRESS_LOG_TO_FILE; fi

	SHOW_WARNING=yes

	display_alert "Starting single build process" "${BOARD}" "info"

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
		KERNEL_ONLY=$(dialog_if_terminal --stdout --title "Choose an option" --backtitle "$backtitle" --no-tags \
			--menu "Select what to build" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		unset options
		[[ -z $KERNEL_ONLY ]] && exit_with_error "No option selected"
	fi

	if [[ -z $KERNEL_CONFIGURE ]]; then
		options+=("no" "Do not change the kernel configuration")
		options+=("yes" "Show a kernel configuration menu before compilation")
		options+=("prebuilt" "Use precompiled packages from Armbian repository")
		KERNEL_CONFIGURE=$(dialog_if_terminal --stdout --title "Choose an option" --backtitle "$backtitle" --no-tags \
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
			BOARD=$(DIALOGRC=$temp_rc dialog_if_terminal --stdout --title "Choose a board" --backtitle "$backtitle" --scrollbar \
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

	display_alert "Sourcing board configuration" "${BOARD}.${BOARD_TYPE}" "info"
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
			BRANCH=$(dialog_if_terminal --stdout --title "Choose a kernel" --backtitle "$backtitle" --colors \
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
		RELEASE=$(dialog_if_terminal --stdout --title "Choose a release package base" --backtitle "$backtitle" \
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
		BUILD_DESKTOP=$(dialog_if_terminal --stdout --title "Choose image type" --backtitle "$backtitle" --no-tags \
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
		BUILD_MINIMAL=$(dialog_if_terminal --stdout --title "Choose image type" --backtitle "$backtitle" --no-tags \
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
		REPOSITORY_INSTALL="u-boot,kernel,bsp,armbian-zsh,armbian-config,armbian-bsp-cli,armbian-firmware${BUILD_DESKTOP:+,armbian-desktop,armbian-bsp-desktop}"

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

function distro_menu() {
	# create a select menu for choosing a distribution based EXPERT status

	local distrib_dir="${1}"

	if [[ -d "${distrib_dir}" && -f "${distrib_dir}/support" ]]; then
		local support_level="$(cat "${distrib_dir}/support")"
		if [[ "${support_level}" != "supported" && $EXPERT != "yes" ]]; then
			:
		else
			local distro_codename="$(basename "${distrib_dir}")"
			local distro_fullname="$(cat "${distrib_dir}/name")"
			local expert_infos=""
			[[ $EXPERT == "yes" ]] && expert_infos="(${support_level})"
			options+=("${distro_codename}" "${distro_fullname} ${expert_infos}")
		fi
	fi

}

function distros_options() {
	for distrib_dir in "config/distributions/"*; do
		distro_menu "${distrib_dir}"
	done
}

# Some utility functions
branch2dir() {
	[[ "${1}" == "head" ]] && echo "HEAD" || echo "${1##*:}"
}
