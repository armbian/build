#!/usr/bin/env bash

# Initialize and prepare the trap managers, one for each of ERR, INT, TERM and EXIT traps.
# Bash goes insane regarding line numbers and other stuff if we try to overwrite the traps.
# This also implements the custom "cleanup" handlers, which always run at the end of build, or when exiting prematurely for any reason.
function traps_init() {
	# shellcheck disable=SC2034 # Array of cleanup handlers.
	declare -g -a trap_manager_cleanup_handlers=()
	# shellcheck disable=SC2034 # Global to avoid doubly reporting ERR/EXIT pairs.
	declare -g -i trap_manager_error_handled=0
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
				if [[ ! ${trap_manager_error_handled} -gt 0 ]]; then
					logging_error_show_log
					display_alert "Error ${trap_exit_code} occurred in main shell" "at ${short_stack}\n${stack_caller}\n" "err"
				fi
			else
				# In a subshell. This trap will run again in the parent shell, so just output a message about it;
				# When the parent shell trap runs, it will show the stack and log.
				display_alert "Error  ${trap_exit_code} occurred in SUBSHELL" "SUBSHELL at ${short_stack}" "err"
			fi
			trap_manager_error_handled=1
			return # Nothing else to do here, let the EXIT trap do the cleanups.
			;;

		EXIT)
			if [[ ${trap_manager_error_handled} -lt 1 ]] && [[ ${trap_exit_code} -gt 0 ]]; then
				logging_error_show_log
				display_alert "Exiting with error ${trap_exit_code}" "at ${short_stack}\n${stack_caller}\n" "err"
				trap_manager_error_handled=1
			fi

			if [[ ${trap_exit_code} -gt 0 ]] && [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
				export ERROR_DEBUG_SHELL=no # dont do it twice
				display_alert "MOUNT" "${MOUNT}" "debug"
				display_alert "SDCARD" "${SDCARD}" "debug"
				display_alert "ERROR_DEBUG_SHELL=yes, starting a shell." "ERROR_DEBUG_SHELL; exit to cleanup." "debug"
				bash < /dev/tty >&2 || true
			fi

			# Run the cleanup handlers, always. pass it the exit code so it keep the red theme of errors in its messages.
			cleanup_exit_code="${trap_exit_code}" run_cleanup_handlers || true

			# If global_final_exit_code is set, use it as the exit code. (used by docker CLI handler)
			if [[ -n "${global_final_exit_code}" ]]; then
				display_alert "Final exit code" "Final exit code ${global_final_exit_code}" "debug"
				# disable the trap, so we don't get called again.
				trap - EXIT
				exit "${global_final_exit_code}"
			fi
			;;
		*)
			display_alert "main_trap_handler" "Unknown trap type '${trap_type}'" "err"
			;;
	esac
}

# Run the cleanup handlers, if any, and clean the cleanup list.
function run_cleanup_handlers() {
	display_alert "run_cleanup_handlers! list:" "${trap_manager_cleanup_handlers[*]}" "cleanup"
	if [[ ${#trap_manager_cleanup_handlers[@]} -lt 1 ]]; then
		return 0 # No handlers set, just return.
	else
		if [[ ${cleanup_exit_code:-0} -gt 0 ]]; then
			display_alert "Cleaning up" "please wait for cleanups to finish" "error"
		else
			display_alert "Cleaning up" "please wait for cleanups to finish" "info"
		fi
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
	local remaining_cleanups=()
	for one_cleanup_handler in "${trap_manager_cleanup_handlers[@]}"; do
		if [[ "${one_cleanup_handler}" != "${callback}" ]]; then
			remaining_cleanups+=("${one_cleanup_handler}")
		else
			run_one_cleanup_handler "${one_cleanup_handler}"
		fi
	done
	trap_manager_cleanup_handlers=("${remaining_cleanups[@]}")
}

function run_one_cleanup_handler() {
	declare one_cleanup_handler="$1"
	display_alert "Running cleanup handler" "${one_cleanup_handler}" "cleanup"

	eval "${one_cleanup_handler}" || {
		display_alert "Cleanup handler failed, this is a severe bug in the build system or extensions" "${one_cleanup_handler}" "err"
	}
}

function remove_all_trap_handlers() {
	# @TODO find usages and kill
	display_alert "calling obsolete method remove_all_trap_handlers()" "not doing anything" "warning"
}

# exit_with_error <message> <highlight>
# a way to terminate build process with verbose error message
function exit_with_error() {
	# Log the error and exit.
	# Everything else will be done by shared trap handling, above.
	local _file="${BASH_SOURCE[1]}"
	local _function=${FUNCNAME[1]}
	local _line="${BASH_LINENO[0]}"

	display_alert "error!" "${1} ${2}" "err"

	#display_alert "Build terminating..." "please wait for cleanups to finish" "err"

	# @TODO: move this into trap handler
	# @TODO: integrate both overlayfs and the FD locking with cleanup logic
	overlayfs_wrapper "cleanup"

	## This does not really make sense. wtf?
	## unlock loop device access in case of starvation # @TODO: hmm, say that again?
	#exec {FD}> /var/lock/armbian-debootstrap-losetup
	#flock -u "${FD}"

	# do NOT close the fd 13 here, otherwise the error will not be logged to logfile...

	exit 43
}

