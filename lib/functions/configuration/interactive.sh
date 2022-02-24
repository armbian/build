function interactive_config_prepare_terminal() {
	if [[ $BUILD_ALL != "yes" && -z $ROOT_FS_CREATE_ONLY ]]; then
		if [[ -t 0 ]]; then # "-t fd return True if file descriptor fd is open and refers to a terminal". 0 = stdin, 1 = stdout, 2 = stderr, 3+ custom
			# override stty size, if stdin is a terminal.
			[[ -n $COLUMNS ]] && stty cols $COLUMNS
			[[ -n $LINES ]] && stty rows $LINES
			export TTY_X=$(($(stty size | awk '{print $2}') - 6)) # determine terminal width
			export TTY_Y=$(($(stty size | awk '{print $1}') - 6)) # determine terminal height
		fi
	fi
	# We'll use this title on all menus
	export backtitle="Armbian building script, https://www.armbian.com | https://docs.armbian.com | (c) 2013-2022 Igor Pecovnik "
}

function interactive_config_ask_kernel() {
	interactive_config_ask_kernel_only
	interactive_config_ask_kernel_configure
}

function interactive_config_ask_kernel_only() {
	# if KERNEL_ONLY, KERNEL_CONFIGURE, BOARD, BRANCH or RELEASE are not set, display selection menu
	[[ -n ${KERNEL_ONLY} ]] && return 0
	options+=("yes" "U-boot and kernel packages")
	options+=("no" "Full OS image for flashing")
	dialog_if_terminal_set_vars --stdout --title "Choose an option" --backtitle "$backtitle" --no-tags --menu "Select what to build" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"
	KERNEL_ONLY="${DIALOG_RESULT}"
	[[ "${DIALOG_EXIT_CODE}" != "0" ]] && exit_with_error "You cancelled interactive during KERNEL_ONLY selection: '${DIALOG_EXIT_CODE}'" "Build cancelled: ${DIALOG_EXIT_CODE}"
	unset options
}

function interactive_config_ask_kernel_configure() {
	[[ -n ${KERNEL_CONFIGURE} ]] && return 0
	options+=("no" "Do not change the kernel configuration")
	options+=("yes" "Show a kernel configuration menu before compilation")
	options+=("prebuilt" "Use precompiled packages from Armbian repository")
	dialog_if_terminal_set_vars --stdout --title "Choose an option" --backtitle "$backtitle" --no-tags --menu "Select the kernel configuration" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"
	KERNEL_CONFIGURE="${DIALOG_RESULT}"
	[[ ${DIALOG_EXIT_CODE} != 0 ]] && exit_with_error "You cancelled interactive during kernel configuration" "Build cancelled"
	unset options
}

function interactive_config_ask_board_list() {
	# if BOARD is not set, display selection menu
	[[ -n ${BOARD} ]] && return 0

	WIP_STATE=supported
	WIP_BUTTON='CSC/WIP/EOS/TVB'
	STATE_DESCRIPTION=' - boards with high level of software maturity'
	temp_rc=$(mktemp) # @TODO: this is a _very_ early call to mktemp - no TMPDIR set yet - it needs to be cleaned-up somehow

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

		DIALOGRC=$temp_rc \
			dialog_if_terminal_set_vars --stdout --title "Choose a board" --backtitle "$backtitle" --scrollbar \
			--colors --extra-label "Show $WIP_BUTTON" --extra-button \
			--menu "Select the target board. Displaying:\n$STATE_DESCRIPTION" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"
		BOARD="${DIALOG_RESULT}"
		STATUS=${DIALOG_EXIT_CODE}

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
		else
			exit_with_error "You cancelled interactive config" "Build cancelled, board not chosen"
		fi
		unset options
	done
}

function interactive_config_ask_branch() {
	# if BRANCH not set, display selection menu
	[[ -n $BRANCH ]] && return 0
	options=()
	[[ $KERNEL_TARGET == *current* ]] && options+=("current" "Recommended. Come with best support")
	[[ $KERNEL_TARGET == *legacy* ]] && options+=("legacy" "Old stable / Legacy")
	[[ $KERNEL_TARGET == *edge* && $EXPERT = yes ]] && options+=("edge" "\Z1Bleeding edge from @kernel.org\Zn")

	# do not display selection dialog if only one kernel branch is available
	if [[ "${#options[@]}" == 2 ]]; then
		BRANCH="${options[0]}"
	else
		dialog_if_terminal_set_vars --stdout --title "Choose a kernel" --backtitle "$backtitle" --colors \
			--menu "Select the target kernel branch\nExact kernel versions depend on selected board" \
			$TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"
		BRANCH="${DIALOG_RESULT}"
	fi
	[[ -z ${BRANCH} ]] && exit_with_error "No kernel branch selected"
	unset options
	return 0
}

function interactive_config_ask_release() {
	[[ $KERNEL_ONLY == yes ]] && return 0 # Don't ask if building packages only.
	[[ -n ${RELEASE} ]] && return 0

	options=()
	distros_options
	dialog_if_terminal_set_vars --stdout --title "Choose a release package base" --backtitle "$backtitle" --menu "Select the target OS release package base" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"
	RELEASE="${DIALOG_RESULT}"
	[[ -z ${RELEASE} ]] && exit_with_error "No release selected"
	unset options
}

function interactive_config_ask_desktop_build() {
	# don't show desktop option if we choose minimal build
	[[ $BUILD_MINIMAL == yes ]] && BUILD_DESKTOP=no

	[[ $KERNEL_ONLY == yes ]] && return 0
	[[ -n ${BUILD_DESKTOP} ]] && return 0
	# read distribution support status which is written to the armbian-release file
	set_distribution_status
	options=()
	options+=("no" "Image with console interface (server)")
	options+=("yes" "Image with desktop environment")
	dialog_if_terminal_set_vars --stdout --title "Choose image type" --backtitle "$backtitle" --no-tags \
		--menu "Select the target image type" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"
	BUILD_DESKTOP="${DIALOG_RESULT}"
	unset options
	[[ -z $BUILD_DESKTOP ]] && exit_with_error "No image type selected"
	if [[ ${BUILD_DESKTOP} == "yes" ]]; then
		BUILD_MINIMAL=no
		SELECTED_CONFIGURATION="desktop"
	fi
	return 0
}

function interactive_config_ask_standard_or_minimal() {
	[[ $KERNEL_ONLY == yes ]] && return 0
	[[ $BUILD_DESKTOP != no ]] && return 0
	[[ -n $BUILD_MINIMAL ]] && return 0
	options=()
	options+=("no" "Standard image with console interface")
	options+=("yes" "Minimal image with console interface")
	dialog_if_terminal_set_vars --stdout --title "Choose image type" --backtitle "$backtitle" --no-tags \
		--menu "Select the target image type" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"
	BUILD_MINIMAL="${DIALOG_RESULT}"
	unset options
	[[ -z $BUILD_MINIMAL ]] && exit_with_error "No standard/minimal selected"
	if [[ $BUILD_MINIMAL == "yes" ]]; then
		SELECTED_CONFIGURATION="cli_minimal"
	else
		SELECTED_CONFIGURATION="cli_standard"
	fi
}
