#!/usr/bin/env bash

# Initialize and prepare the trap managers, one for each of ERR, INT, TERM and EXIT traps.
# Bash goes insane regarding line numbers and other stuff if we try to overwrite the traps.
# This also implements the custom "cleanup" handlers, which always run at the end of build, or when exiting prematurely for any reason.
function traps_init() {
	# shellcheck disable=SC2034 # Array of cleanup handlers.
	declare -a trap_manager_cleanup_handlers=()
	# shellcheck disable=SC2034 # Global to avoid doubly reporting ERR/EXIT pairs.
	declare -i trap_manager_error_handled=0
	trap 'main_trap_handler "ERR" "$?"' ERR
	trap 'main_trap_handler "EXIT" "$?"' EXIT
	trap 'main_trap_handler "INT" "$?"' INT
	trap 'main_trap_handler "TERM" "$?"' TERM
}

# This is setup early in compile.sh as a trap handler for ERR, EXIT and INT signals.
# There are arrays trap_manager_error_handlers=() trap_manager_exit_handlers=() trap_manager_int_handlers=()
# that will receive the actual handlers.
# First param is the type of trap, the second is the value of "$?"
# In order of occurrence.
# 1) Ctrl-C causes INT [stack unreliable], then ERR, then EXIT with trap_exit_code > 0
# 2) Stuff failing causes ERR [stack OK], then EXIT with trap_exit_code > 0
# 3) exit_with_error causes EXIT [stack OK, with extra frame] directly with trap_exit_code == 43
# 4) EXIT can also be called directly [stack unreliable], with trap_exit_code == 0 if build successful.
# So the EXIT trap will do:
# - show stack, if not previously shown (trap_manager_error_handled==0), and if trap_exit_code > 0
# - allow for debug shell, if trap_exit_code > 0
# - call all the cleanup functions (always)
function main_trap_handler() {
	local trap_type="${1}"
	local trap_exit_code="${2}"
	local stack_caller short_stack
	stack_caller="$(show_caller_full)"
	short_stack="${BASH_SOURCE[1]}:${BASH_LINENO[0]}"

	display_alert "main_trap_handler" "${trap_type} and ${trap_exit_code} trap_manager_error_handled:${trap_manager_error_handled} short_stack:${short_stack}" "trap"

	case "${trap_type}" in
		TERM | INT)
			display_alert "Build interrupted" "Build interrupted by SIG${trap_type}" "warn"
			trap_manager_error_handled=1
			return # Nothing else to do here. Let the ERR trap show the stack, and the EXIT trap do cleanups.
			;;

		ERR)
			# If error occurs in subshell (eg: inside $()), we would show the error twice.
			# Determine if we're in a subshell, and if so, output a single message.
			# BASHPID is the current subshell; $$ is parent shell pid
			if [[ "${BASHPID}" == "${$}" ]]; then
				# Not in subshell, dump the error, complete with log, and show the stack.
				logging_error_show_log
				display_alert "Error occurred in main shell" "code ${trap_exit_code} at ${short_stack}\n${stack_caller}\n" "err"
			else
				# In a subshell. This trap will run again in the parent shell, so just output a message about it;
				# When the parent shell trap runs, it will show the stack and log.
				display_alert "Error occurred in SUBSHELL" "SUBSHELL: code ${trap_exit_code} at ${short_stack}" "err"
			fi
			trap_manager_error_handled=1
			return # Nothing else to do here, let the EXIT trap do the cleanups.
			;;

		EXIT)
			if [[ ${trap_manager_error_handled} -lt 1 ]] && [[ ${trap_exit_code} -gt 0 ]]; then
				logging_error_show_log
				display_alert "Exit with error detected" "${trap_exit_code} at ${short_stack} -\n${stack_caller}\n" "err"
				trap_manager_error_handled=1
			fi

			if [[ ${trap_exit_code} -gt 0 ]] && [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
				export ERROR_DEBUG_SHELL=no # dont do it twice
				display_alert "MOUNT" "${MOUNT}" "debug"
				display_alert "SDCARD" "${SDCARD}" "debug"
				display_alert "ERROR_DEBUG_SHELL=yes, starting a shell." "ERROR_DEBUG_SHELL; exit to cleanup." "debug"
				bash < /dev/tty >&2 || true
			fi

			# Run the cleanup handlers, always.
			run_cleanup_handlers || true
			;;
	esac
}

# Run the cleanup handlers, if any, and clean the cleanup list.
function run_cleanup_handlers() {
	display_alert "run_cleanup_handlers! list:" "${trap_manager_cleanup_handlers[*]}" "cleanup"
	if [[ ${#trap_manager_cleanup_handlers[@]} -lt 1 ]]; then
		return 0 # No handlers set, just return.
	else
		display_alert "Cleaning up" "please wait for cleanups to finish" "debug"
	fi
	# Loop over the handlers, execute one by one. Ignore errors.
	# IMPORTANT: cleanups are added first to the list, so cleanups run in the reverse order they were added.
	local one_cleanup_handler
	for one_cleanup_handler in "${trap_manager_cleanup_handlers[@]}"; do
		run_one_cleanup_handler "${one_cleanup_handler}"
	done
	# Clear the cleanup handler list, so they don't accidentally run again.
	trap_manager_cleanup_handlers=()
}

# Adds a callback for trap types; first and only argument is eval code to call during cleanup. If such, that needs proper quoting (@Q)
function add_cleanup_handler() {
	if [[ $# -gt 1 ]]; then
		exit_with_error "add_cleanup_handler: too many params"
	fi
	local callback="$1" # simple function name or @Q quoted eval code
	# validate
	if [[ -z "${callback}" ]]; then
		exit_with_error "add_cleanup_handler: no callback specified"
	fi

	display_alert "Add callback as cleanup handler" "${callback}" "cleanup"
	# IMPORTANT: cleanups are added first to the list, so they're executed in reverse order.
	trap_manager_cleanup_handlers=("${callback}" "${trap_manager_cleanup_handlers[@]}")
}

function execute_and_remove_cleanup_handler() {
	local callback="$1"
	display_alert "Execute and remove cleanup handler" "${callback}" "cleanup"
	local remaning_cleanups=()
	for one_cleanup_handler in "${trap_manager_cleanup_handlers[@]}"; do
		if [[ "${one_cleanup_handler}" != "${callback}" ]]; then
			remaning_cleanups+=("${one_cleanup_handler}")
		else
			run_one_cleanup_handler "${one_cleanup_handler}"
		fi
	done
	trap_manager_cleanup_handlers=("${remaning_cleanups[@]}")
}

function run_one_cleanup_handler() {
	declare one_cleanup_handler="$1"
	display_alert "Running cleanup handler" "${one_cleanup_handler}" "cleanup"

	eval "${one_cleanup_handler}" || {
		display_alert "Cleanup handler failed, this is a severe bug in the build system or extensions" "${one_cleanup_handler}" "err"
	}
}

function remove_all_trap_handlers() {
	display_alert "Will remove ALL trap handlers, for a clean exit..." "" "cleanup"
}

# exit_with_error <message> <highlight>
# a way to terminate build process with verbose error message
function exit_with_error() {
	# Log the error and exit.
	# Everything else will be done by shared trap handling, above.
	local _file="${BASH_SOURCE[1]}"
	local _function=${FUNCNAME[1]}
	local _line="${BASH_LINENO[0]}"

	display_alert "error: ${1}" "${2} in ${_function}() at ${_file}:${_line}" "err"

	# @TODO: move this into trap handler
	# @TODO: integrate both overlayfs and the FD locking with cleanup logic
	display_alert "Build terminating... wait for cleanups..." "" "err"
	overlayfs_wrapper "cleanup"

	## This does not really make sense. wtf?
	## unlock loop device access in case of starvation # @TODO: hmm, say that again?
	#exec {FD}> /var/lock/armbian-debootstrap-losetup
	#flock -u "${FD}"

	exit 43
}

# This exits, unless user presses ENTER. If not interactive, user will be unable to comply and the script will exit.
function exit_if_countdown_not_aborted() {
	# parse
	declare -i loops="${1}"
	declare reason="${2}"
	# validate
	[[ -z "${loops}" ]] && exit_with_error "countdown_to_exit_or_just_exit_if_noninteractive() called without a number of loops"
	[[ -z "${reason}" ]] && exit_with_error "countdown_to_exit_or_just_exit_if_noninteractive() called without a reason"

	# If not interactive, just exit.
	if [[ ! -t 1 ]]; then
		exit_with_error "Exiting due to '${reason}' - not interactive, exiting immediately."
	fi

	display_alert "Problem detected" "${reason}" "err"
	display_alert "Exiting in ${loops} seconds" "Press <Ctrl-C> to abort, <Enter> to ignore and continue" "err"
	echo -n "Counting down: "
	for i in $(seq 1 "${loops}"); do
		declare stop_waiting=0
		declare keep_waiting=0
		timeout --foreground 1 bash -c "read -n1; echo \$REPLY" && stop_waiting=1 || keep_waiting=1
		if [[ "$stop_waiting" == "1" ]]; then
			display_alert "User pressed ENTER, continuing, albeit" "${reason}" "wrn"
			return 0
		fi
		echo -n "$((10 - i))... " >&2
	done

	echo "" >&2 # No newlines during countdown, so break one here

	# Countdown finished, exit.
	exit_with_error "Exiting due to '${reason}'"
}
