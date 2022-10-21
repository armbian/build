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

	display_alert "main_trap_handler" "${trap_type} and ${trap_exit_code} trap_manager_error_handled:${trap_manager_error_handled}" "trap"

	case "${trap_type}" in
		TERM | INT)
			display_alert "Build interrupted" "Build interrupted by SIG${trap_type}" "warn"
			trap_manager_error_handled=1
			return # Nothing else to do here. Let the ERR trap show the stack, and the EXIT trap do cleanups.
			;;

		ERR)
			logging_error_show_log
			display_alert "Error occurred" "code ${trap_exit_code} at ${short_stack}\n${stack_caller}\n" "err"
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
	local one_cleanup_handler
	for one_cleanup_handler in "${trap_manager_cleanup_handlers[@]}"; do
		display_alert "Running cleanup handler" "${one_cleanup_handler}" "debug"
		"${one_cleanup_handler}" || true
	done
	# Clear the cleanup handler list, so they don't accidentally run again.
	trap_manager_cleanup_handlers=()
}

# Adds a callback for trap types; first argument is function name; extra params are the types to add for.
function add_cleanup_handler() {
	local callback="$1"
	display_alert "Add callback as cleanup handler" "${callback}" "cleanup"
	trap_manager_cleanup_handlers+=("$callback")
}

function execute_and_remove_cleanup_handler() {
	local callback="$1"
	display_alert "Execute and remove cleanup handler" "${callback}" "cleanup"
	# @TODO implement!
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
	# unlock loop device access in case of starvation # @TODO: hmm, say that again?
	exec {FD}> /var/lock/armbian-debootstrap-losetup
	flock -u "${FD}"

	exit 43
}
