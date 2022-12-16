#!/usr/bin/env bash

# Stuff involving dialog

# rpardini: dialog reports what happened via nonzero exit codes.
# we also want to capture the stdout of dialog.
# this is a helper function that handles the error logging on/off and does the capturing
# then reports via exported variables, which the caller can/should test for later.
# warning: this will exit with error if stdin/stdout/stderr is not a terminal or running under CI, or if dialog not installed
# otherwise it will NOT exit with error, even if user cancelled.
# This is a boring topic, see https://askubuntu.com/questions/491509/how-to-get-dialog-box-input-directed-to-a-variable
function dialog_if_terminal_set_vars() {
	export DIALOG_RESULT=""
	export DIALOG_EXIT_CODE=0

	[[ ! -t 0 ]] && exit_with_error "stdin is not a terminal. can't use dialog." "dialog_if_terminal_set_vars ${*}" "err"
	[[ ! -t 1 ]] && exit_with_error "stdout is not a terminal. can't use dialog." "dialog_if_terminal_set_vars ${*}" "err"
	[[ ! -t 2 ]] && exit_with_error "stderr is not a terminal. can't use dialog." "dialog_if_terminal_set_vars ${*}" "err"

	[[ "${CI}" == "true" ]] && exit_with_error "CI=true. can't use dialog." "dialog_if_terminal_set_vars ${*}" "err"

	[[ ! -f /usr/bin/dialog ]] && exit_with_error "Dialog is not installed at /usr/bin/dialog" "dialog_if_terminal_set_vars ${*}" "err"

	set +e          # allow errors through
	set +o errtrace # do not trap errors inside a subshell/function
	set +o errexit  # disable

	exec 3>&1                              # open fd 3...
	DIALOG_RESULT=$(dialog "$@" 2>&1 1>&3) # juggle fds and capture.
	DIALOG_EXIT_CODE=$?                    # get the exit code.
	exec 3>&-                              # close fd 3...

	set -e          # back to normal
	set -o errtrace # back to normal
	set -o errexit  # back to normal
	
	# clear the screen after dialog exits; that way we can see the log output that comes after it?
	clear

	return 0 # always success, caller must check DIALOG_EXIT_CODE and DIALOG_RESULT
}

# Myy : Menu configuration for choosing desktop configurations
dialog_menu() {
	export DIALOG_MENU_RESULT=""
	provided_title=$1
	provided_backtitle=$2
	provided_menuname=$3
	dialog_if_terminal_set_vars --title "$provided_title" --backtitle "${provided_backtitle}" --menu "$provided_menuname" $TTY_Y $TTY_X $((TTY_Y - 8)) "${@:4}"
	DIALOG_MENU_RESULT="${DIALOG_RESULT}"
	return $DIALOG_EXIT_CODE
}

# Almost identical, but is a checklist instead of menu
dialog_checklist() {
	export DIALOG_CHECKLIST_RESULT=""
	provided_title=$1
	provided_backtitle=$2
	provided_menuname=$3
	dialog_if_terminal_set_vars --title "${provided_title}" --backtitle "${provided_backtitle}" --checklist "${provided_menuname}" $TTY_Y $TTY_X $((TTY_Y - 8)) "${@:4}"
	DIALOG_CHECKLIST_RESULT="${DIALOG_RESULT}"
	return $DIALOG_EXIT_CODE
}

# Other menu stuff
show_developer_warning() {
	local temp_rc
	temp_rc=$(mktemp) # @TODO: this is a _very_ early call to mktemp - no TMPDIR set yet - it needs to be cleaned-up somehow
	cat <<- 'EOF' > "${temp_rc}"
		screen_color = (WHITE,RED,ON)
	EOF
	local warn_text="You are switching to the \Z1EXPERT MODE\Zn

	This allows building experimental configurations that are provided
	\Z1AS IS\Zn to developers and expert users,
	\Z1WITHOUT ANY RESPONSIBILITIES\Zn from the Armbian team:

	- You are using these configurations \Z1AT YOUR OWN RISK\Zn
	- Bug reports related to the dev kernel, CSC, WIP and EOS boards
	\Z1will be closed without a discussion\Zn
	- Forum posts related to dev kernel, CSC, WIP and EOS boards
	should be created in the \Z2\"Community forums\"\Zn section
	"
	DIALOGRC=$temp_rc dialog_if_terminal_set_vars --title "Expert mode warning" --backtitle "${backtitle}" --colors --defaultno --no-label "I do not agree" --yes-label "I understand and agree" --yesno "$warn_text" "${TTY_Y}" "${TTY_X}"
	[[ ${DIALOG_EXIT_CODE} -ne 0 ]] && exit_with_error "Error switching to the expert mode"
	SHOW_WARNING=no
}

# Stuff that was in config files
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
