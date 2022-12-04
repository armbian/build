#!/usr/bin/env bash
function interactive_config_prepare_terminal() {
	if [[ -z $ROOT_FS_CREATE_ONLY ]]; then
		# override stty size
		[[ -n $COLUMNS ]] && stty cols $COLUMNS
		[[ -n $LINES ]] && stty rows $LINES
		TTY_X=$(($(stty size | awk '{print $2}') - 6)) # determine terminal width
		TTY_Y=$(($(stty size | awk '{print $1}') - 6)) # determine terminal height
	fi

	# We'll use this title on all menus
	backtitle="Armbian building script, https://www.armbian.com | https://docs.armbian.com | (c) 2013-2021 Igor Pecovnik "
}

function interactive_config_ask_kernel() {
#	interactive_config_ask_kernel_only
	interactive_config_ask_kernel_configure
}

function interactive_config_ask_kernel_only() {
	if [[ -z $KERNEL_ONLY ]]; then

		options+=("yes" "U-boot and kernel packages")
		options+=("no" "Full OS image for flashing")
		KERNEL_ONLY=$(dialog --stdout --title "Choose an option" --backtitle "$backtitle" --no-tags \
			--menu "Select what to build" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		unset options
		[[ -z $KERNEL_ONLY ]] && exit_with_error "No option selected"

	fi
}

function interactive_config_ask_kernel_configure() {
	if [[ -z $KERNEL_CONFIGURE ]]; then

		options+=("no" "Do not change the kernel configuration")
		options+=("yes" "Show a kernel configuration menu before compilation")
		options+=("prebuilt" "Use precompiled packages (maintained hardware only)")
		KERNEL_CONFIGURE=$(dialog --stdout --title "Choose an option" --backtitle "$backtitle" --no-tags \
			--menu "Select the kernel configuration" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		unset options
		[[ -z $KERNEL_CONFIGURE ]] && exit_with_error "No option selected"

	fi
}

function interactive_config_ask_board_list() {
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
}

function interactive_config_ask_branch() {
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
}

function interactive_config_ask_release() {
	if [[ -z "$RELEASE" ]]; then

		options=()

		distros_options

		RELEASE=$(dialog --stdout --title "Choose a release package base" --backtitle "$backtitle" \
			--menu "Select the target OS release package base" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		[[ -z $RELEASE ]] && exit_with_error "No release selected"

		unset options
	fi
}

function interactive_config_ask_desktop_build() {
	# don't show desktop option if we choose minimal build
	if [[ $HAS_VIDEO_OUTPUT == no || $BUILD_MINIMAL == yes ]]; then
		BUILD_DESKTOP=no
	elif [[ -z "$BUILD_DESKTOP" ]]; then

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
}

function interactive_config_ask_standard_or_minimal() {
	if [[ $BUILD_DESKTOP == no && -z $BUILD_MINIMAL ]]; then

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
}
