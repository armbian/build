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
	echo -n "Counting down: " >&2
	for i in $(seq 1 "${loops}"); do
		declare stop_waiting=0
		declare keep_waiting=0
		timeout --foreground 1 bash -c "read -n1; echo \$REPLY" && stop_waiting=1 || keep_waiting=1
		if [[ "$stop_waiting" == "1" ]]; then
			display_alert "User pressed ENTER, continuing, albeit" "${reason}" "wrn"
			return 0
		fi
		echo -n "$((loops - i))... " >&2
	done

	echo "" >&2 # No newlines during countdown, so break one here

	# Countdown finished, exit.
	exit_with_error "Exiting due to '${reason}'"
}

function countdown_and_continue_if_not_aborted() {
	# parse
	declare -i loops="${1}"
	# validate
	[[ -z "${loops}" ]] && exit_with_error "countdown_and_continue_if_not_aborted() called without a number of loops"

	echo -n "Counting down: " >&2
	for i in $(seq 1 "${loops}"); do
		declare stop_waiting=0
		declare keep_waiting=0
		timeout --foreground 1 bash -c "read -n1; echo \$REPLY" && stop_waiting=1 || keep_waiting=1
		if [[ "$stop_waiting" == "1" ]]; then
			display_alert "User pressed a key, continuing faster..." "" "info"
			return 0
		fi
		echo -n "$((loops - i))... " >&2
	done

	echo "" >&2 # No newlines during countdown, so break one here
	return 0
}
