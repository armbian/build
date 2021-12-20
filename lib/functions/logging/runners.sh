# shortcut
function chroot_sdcard_apt_get_install() {
	chroot_sdcard_apt_get --no-install-recommends install "$@"
}

function chroot_sdcard_apt_get() {
	local -a apt_params=("-${APT_OPTS:-yqq}")
	[[ $NO_APT_CACHER != yes ]] && apt_params+=(
		-o "Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\""
		-o "Acquire::http::Proxy::localhost=\"DIRECT\""
		-o "Dpkg::Use-Pty=0" # Please be quiet
	)
	# IMPORTANT: this function returns the exit code of last statement, in this case chroot (which gets its result from bash which calls apt-get)
	chroot_sdcard DEBIAN_FRONTEND=noninteractive apt-get "${apt_params[@]}" "$@"
}

# please, please, unify around this function. if SDCARD is not enough, I'll make a mount version.
function chroot_sdcard() {
	run_host_command_logged_raw chroot "${SDCARD}" /bin/bash -e -c "$*"
}

function chroot_custom_long_running() {
	local target=$1
	shift
	local _exit_code=1
	if [[ "${SHOW_LOG}" == "yes" ]] || [[ "${CI}" == "true" ]]; then
		run_host_command_logged_raw chroot "${target}" /bin/bash -e -c "$*"
		_exit_code=$?
	else
		run_host_command_logged_raw chroot "${target}" /bin/bash -e -c "$*" | pv -N "$(logging_echo_prefix_for_pv "${INDICATOR:-compile}")" --progress --timer --line-mode --force --cursor --delay-start 0 -i "0.5"
		_exit_code=$?
	fi
	return $_exit_code
}

function chroot_custom() {
	local target=$1
	shift
	run_host_command_logged_raw chroot "${target}" /bin/bash -e -c "$*"
}

# for long-running, host-side expanded bash invocations.
# the user gets a pv-based spinner based on the number of lines that flows to stdout (log messages).
# the raw version is already redirect stderr to stdout, and we'll be running under do_with_logging,
# so: _the stdout must flow_!!!
function run_host_command_logged_long_running() {
	local _exit_code=1
	if [[ "${SHOW_LOG}" == "yes" ]] || [[ "${CI}" == "true" ]]; then
		run_host_command_logged_raw /bin/bash -e -c "$*"
		_exit_code=$?
	else
		run_host_command_logged_raw /bin/bash -e -c "$*" | pv -N "$(logging_echo_prefix_for_pv "${INDICATOR:-compile}")" --progress --timer --line-mode --force --cursor --delay-start 0 -i "0.5"
		_exit_code=$?
	fi
	return $_exit_code
}

# run_host_command_logged is the very basic, should be used for everything, but, please use helpers above, this is very low-level.
function run_host_command_logged() {
	run_host_command_logged_raw /bin/bash -e -c "$*"
}

# do NOT use directly, it does NOT expand the way it should (through bash)
function run_host_command_logged_raw() {
	# Log the command to the current logfile, so it has context of what was run.
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo "       " >> "${CURRENT_LOGFILE}" # blank line for reader's benefit
		echo "-->" "$*" " <- at $(date --utc)" >> "${CURRENT_LOGFILE}"
	fi

	# uncomment when desperate to understand what's going on
	# echo "cmd about to run" "$@" >&2

	local exit_code=666
	"$@" 2>&1 # redirect stderr to stdout. $* is NOT $@!
	exit_code=$?
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo "--> cmd exited with code ${exit_code} at $(date --utc)" >> "${CURRENT_LOGFILE}"
	fi
	if [[ $exit_code != 0 ]]; then
		display_alert "cmd exited with code ${exit_code}" "$*" "wrn"
	fi
	return $exit_code
}

# @TODO: logging: used by desktop.sh exclusively. let's unify?
run_on_sdcard() {
	chroot_sdcard "${@}"
}
