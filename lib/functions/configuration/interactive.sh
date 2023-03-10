#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

#!/usr/bin/env bash

function interactive_config_prepare_terminal() {
	if [[ -z $ROOT_FS_CREATE_ONLY ]]; then
		if [[ -t 0 ]]; then # "-t fd return True if file descriptor fd is open and refers to a terminal". 0 = stdin, 1 = stdout, 2 = stderr, 3+ custom
			# override stty size, if stdin is a terminal.
			[[ -n $COLUMNS ]] && stty cols $COLUMNS
			[[ -n $LINES ]] && stty rows $LINES
			export TTY_X=$(($(stty size | awk '{print $2}') - 6)) # determine terminal width
			export TTY_Y=$(($(stty size | awk '{print $1}') - 6)) # determine terminal height
		fi
	fi
	# We'll use this title on all menus
	declare -g -r backtitle="Armbian building script, https://www.armbian.com | https://docs.armbian.com | (c) 2013-2023 Igor Pecovnik "
}

function interactive_finish() {
	unset TTY_X
	unset TTY_Y
	unset options
	unset DIALOG_EXIT_CODE
	unset WIP_STATE
	unset SHOW_WARNING
}

function interactive_config_ask_kernel() {
	interactive_config_ask_kernel_only
	interactive_config_ask_kernel_configure
}

function interactive_config_ask_kernel_only() {
	# if KERNEL_ONLY, KERNEL_CONFIGURE, BOARD, BRANCH or RELEASE are not set, display selection menu
	[[ -n ${KERNEL_ONLY} ]] && return 0
	options+=("no" "Full OS image for flashing")
	options+=("yes" "U-boot and kernel packages ONLY")
	dialog_if_terminal_set_vars --title "Choose an option" --backtitle "$backtitle" --no-tags --menu "Select what to build" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"
	KERNEL_ONLY="${DIALOG_RESULT}"
	[[ "${DIALOG_EXIT_CODE}" != "0" ]] && exit_with_error "You cancelled interactive during KERNEL_ONLY selection: '${DIALOG_EXIT_CODE}'" "Build cancelled: ${DIALOG_EXIT_CODE}"
	unset options
}

function interactive_config_ask_kernel_configure() {
	[[ -n ${KERNEL_CONFIGURE} ]] && return 0
	options+=("no" "Do not change the kernel configuration")
	options+=("yes" "Show a kernel configuration menu before compilation")
	#options+=("prebuilt" "Use precompiled packages (maintained hardware only)") # @TODO armbian-next does not support this, I think.
	dialog_if_terminal_set_vars --title "Choose an option" --backtitle "$backtitle" --no-tags --menu "Select the kernel configuration" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"
	KERNEL_CONFIGURE="${DIALOG_RESULT}"
	[[ ${DIALOG_EXIT_CODE} != 0 ]] && exit_with_error "You cancelled interactive during kernel configuration" "Build cancelled"
	unset options
}

# Required usage:
# declare -a arr_all_board_names=() arr_all_board_options=()                                                                                              # arrays
# declare -A dict_all_board_types=() dict_all_board_source_files=() dict_all_board_descriptions=()                                                        # dictionaries
# get_list_of_all_buildable_boards arr_all_board_names arr_all_board_options dict_all_board_types dict_all_board_source_files dict_all_board_descriptions # invoke
function get_list_of_all_buildable_boards() {
	display_alert "Generating list of all available boards" "might take a while" ""
	local -a board_types=("conf")
	[[ "${WIP_STATE}" != "supported" ]] && board_types+=("wip" "csc" "eos" "tvb")
	local -a board_file_paths=("${SRC}/config/boards" "${USERPATCHES_PATH}/config/boards")

	# local -n is a name reference, see https://www.linuxjournal.com/content/whats-new-bash-parameter-expansion
	# it works with arrays and associative arrays/dictionaries
	local -n ref_arr_all_board_names="${1}"
	[[ "${2}" != "" ]] && local -n ref_arr_all_board_options="${2}" # optional
	local -n ref_dict_all_board_types="${3}"
	local -n ref_dict_all_board_source_files="${4}"
	[[ "${5}" != "" ]] && local -n ref_dict_all_board_descriptions="${5}" # optional

	declare -i prepare_options=0
	if [[ "${2}" != "" || "${5}" != "" ]]; then # only if second or fifth reference specified, otherwise too costly
		prepare_options=1
	fi

	local board_file_path board_type full_board_file
	for board_file_path in "${board_file_paths[@]}"; do
		[[ ! -d "${board_file_path}" ]] && continue
		for board_type in "${board_types[@]}"; do
			for full_board_file in "${board_file_path}"/*."${board_type}"; do
				[[ "${full_board_file}" == *"*"* ]] && continue # ignore non-matches, due to bash's (non-)globbing behaviour
				local board_name board_desc
				board_name="$(basename "${full_board_file}" | cut -d'.' -f1)"
				ref_dict_all_board_types["${board_name}"]="${board_type}"
				ref_dict_all_board_source_files["${board_name}"]="${ref_dict_all_board_source_files["${board_name}"]} ${full_board_file}" # accumulate, will have extra space
				if [[ ${prepare_options} -gt 0 ]]; then
					board_desc="$(head -1 "${full_board_file}" | cut -d'#' -f2)"
					ref_dict_all_board_descriptions["${board_name}"]="${board_desc}"
				fi
			done
		done
	done

	if [[ ${prepare_options} -gt 0 ]]; then
		# get a sorted list of boards across all types
		declare ref_arr_all_board_names_unsorted=("${!ref_dict_all_board_types[@]}") # Expand the keys of one of the dicts, that's the list of boards (unsorted)
		declare -a ref_arr_all_board_names_sorted=()
		readarray -t ref_arr_all_board_names_sorted < <(printf '%s\n' "${ref_arr_all_board_names_unsorted[@]}" | sort -h)
		ref_arr_all_board_names=("${ref_arr_all_board_names_sorted[@]}")

		# prepare the options for the dialog menu; this is sorted the same order as the boards.
		for board_name in "${ref_arr_all_board_names[@]}"; do
			ref_arr_all_board_options+=("${board_name}" "\Z1(${ref_dict_all_board_types["${board_name}"]})\Zn ${ref_dict_all_board_descriptions["${board_name}"]}")
		done
	else
		ref_arr_all_board_names=("${!ref_dict_all_board_types[@]}") # Expand the keys of one of the dicts, that's the list of boards (unsorted)
	fi

	return 0
}

function interactive_config_ask_board_list() {
	# if BOARD is not set, display selection menu, otherwise return success
	[[ -n ${BOARD} ]] && return 0

	declare WIP_STATE=supported
	if [[ "${EXPERT}" == "yes" ]]; then
		display_alert "Expert mode!" "You can select all boards" "info"
		WIP_STATE=unsupported
	fi

	declare WIP_BUTTON='CSC/WIP/EOS/TVB'
	declare STATE_DESCRIPTION=' - boards with high level of software maturity'
	declare temp_rc
	temp_rc=$(mktemp) # @TODO: this is a _very_ early call to mktemp - no TMPDIR set yet - it needs to be cleaned-up somehow

	while true; do
		declare -a arr_all_board_names=() arr_all_board_options=()                                                                                              # arrays
		declare -A dict_all_board_types=() dict_all_board_source_files=() dict_all_board_descriptions=()                                                        # dictionaries
		get_list_of_all_buildable_boards arr_all_board_names arr_all_board_options dict_all_board_types dict_all_board_source_files dict_all_board_descriptions # invoke
		echo > "${temp_rc}"                                                                                                                                     # zero out the rcfile to start
		if [[ $WIP_STATE != supported ]]; then                                                                                                                  # be if wip csc etc included. I personally disagree here.
			cat <<- 'EOF' > "${temp_rc}"
				dialog_color = (RED,WHITE,OFF)
				screen_color = (WHITE,RED,ON)
				tag_color = (RED,WHITE,ON)
				item_selected_color = (WHITE,RED,ON)
				tag_selected_color = (WHITE,RED,ON)
				tag_key_selected_color = (WHITE,RED,ON)
			EOF
		fi

		DIALOGRC=$temp_rc \
			dialog_if_terminal_set_vars --title "Choose a board" --backtitle "$backtitle" --scrollbar \
			--colors --extra-label "Show $WIP_BUTTON" --extra-button \
			--menu "Select the target board. Displaying:\n$STATE_DESCRIPTION" $TTY_Y $TTY_X $((TTY_Y - 8)) "${arr_all_board_options[@]}"
		BOARD="${DIALOG_RESULT}"
		declare STATUS=${DIALOG_EXIT_CODE}

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
				EXPERT=no # @TODO: this overrides an "expert" mode that could be set on by the user. revert to original one?
			fi
			continue
		elif [[ $STATUS == 0 ]]; then
			break
		else
			exit_with_error "You cancelled interactive config" "Build cancelled, board not chosen"
		fi
	done
}

function interactive_config_ask_branch() {
	# if BRANCH not set, display selection menu
	if [[ -n $BRANCH ]]; then
		display_alert "Already set BRANCH, skipping interactive" "${BRANCH}" "debug"
		return 0
	fi
	declare -a options=()
	[[ $KERNEL_TARGET == *current* ]] && options+=("current" "Recommended. Usually an LTS kernel")
	[[ $KERNEL_TARGET == *legacy* ]] && options+=("legacy" "Old stable / Legacy / Vendor kernel")
	[[ $KERNEL_TARGET == *edge* ]] && options+=("edge" "Bleeding edge / latest possible")

	dialog_if_terminal_set_vars --title "Choose a kernel" --backtitle "$backtitle" --colors \
		--menu "Select the target kernel branch.\nSelected BOARD='${BOARD}'\nExact kernel versions depend on selected board and its family." \
		$TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"

	BRANCH="${DIALOG_RESULT}"

	[[ -z ${BRANCH} ]] && exit_with_error "No kernel branch selected"
	return 0
}

function interactive_config_ask_release() {
	[[ $KERNEL_ONLY == yes ]] && return 0 # Don't ask if building packages only.
	[[ -n ${RELEASE} ]] && return 0

	declare -a options=()
	distros_options
	dialog_if_terminal_set_vars --title "Choose a release package base" --backtitle "$backtitle" --menu "Select the target OS release package base; selected BRANCH='${BRANCH}'" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"
	RELEASE="${DIALOG_RESULT}"
	[[ -z ${RELEASE} ]] && exit_with_error "No release selected"

	return 0 # shortcircuit above!
}

function interactive_config_ask_desktop_build() {
	# don't show desktop option if we choose minimal build
	[[ $HAS_VIDEO_OUTPUT == no || $BUILD_MINIMAL == yes ]] && BUILD_DESKTOP=no

	[[ $KERNEL_ONLY == yes ]] && return 0
	[[ -n ${BUILD_DESKTOP} ]] && return 0

	# read distribution support status which is written to the armbian-release file
	set_distribution_status
	options=()
	options+=("no" "Image with console interface (server)")
	options+=("yes" "Image with desktop environment")
	dialog_if_terminal_set_vars --title "Choose image type" --backtitle "$backtitle" --no-tags \
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
	dialog_if_terminal_set_vars --title "Choose image type" --backtitle "$backtitle" --no-tags \
		--menu "Select the target image type" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}"
	BUILD_MINIMAL="${DIALOG_RESULT}"
	unset options
	[[ -z $BUILD_MINIMAL ]] && exit_with_error "No standard/minimal selected"
	if [[ $BUILD_MINIMAL == "yes" ]]; then
		SELECTED_CONFIGURATION="cli_minimal"
	else
		SELECTED_CONFIGURATION="cli_standard"
	fi
	return 0
}
