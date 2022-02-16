# shortcut
function chroot_sdcard_apt_get_install() {
	chroot_sdcard_apt_get --no-install-recommends install "$@"
}

function chroot_sdcard_apt_get() {
	local -a apt_params=("-${APT_OPTS:-y}")
	[[ $NO_APT_CACHER != yes ]] && apt_params+=(
		-o "Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\""
		-o "Acquire::http::Proxy::localhost=\"DIRECT\""
	)
	apt_params+=(-o "Dpkg::Use-Pty=0") # Please be quiet
	# IMPORTANT: this function returns the exit code of last statement, in this case chroot (which gets its result from bash which calls apt-get)
	chroot_sdcard DEBIAN_FRONTEND=noninteractive apt-get "${apt_params[@]}" "$@"
}

# please, please, unify around this function. if SDCARD is not enough, I'll make a mount version.
function chroot_sdcard() {
	TMPDIR="" run_host_command_logged_raw chroot "${SDCARD}" /bin/bash -e -c "$*"
}

# This should be used if you need to capture the stdout produced by the command. It is NOT logged, and NOT run thru bash, and NOT quoted.
function chroot_sdcard_with_stdout() {
	TMPDIR="" chroot "${SDCARD}" "$@"
}

function chroot_custom_long_running() {
	local target=$1
	shift

	# @TODO: disabled, the pipe causes the left-hand side to subshell and caos ensues.
	# local _exit_code=1
	# if [[ "${SHOW_LOG}" == "yes" ]] || [[ "${CI}" == "true" ]]; then
	# 	TMPDIR="" run_host_command_logged_raw chroot "${target}" /bin/bash -e -c "$*"
	# 	_exit_code=$?
	# else
	# 	TMPDIR="" run_host_command_logged_raw chroot "${target}" /bin/bash -e -c "$*" | pv -N "$(logging_echo_prefix_for_pv "${INDICATOR:-compile}")" --progress --timer --line-mode --force --cursor --delay-start 0 -i "0.5"
	# 	_exit_code=$?
	# fi
	# return $_exit_code

	TMPDIR="" run_host_command_logged_raw chroot "${target}" /bin/bash -e -c "$*"
}

function chroot_custom() {
	local target=$1
	shift
	TMPDIR="" run_host_command_logged_raw chroot "${target}" /bin/bash -e -c "$*"
}

# for deb building.
function fakeroot_dpkg_deb_build() {
	display_alert "Building .deb package" "$(basename "${3:-${2:-${1}}}" || true)" "debug"
	run_host_command_logged_raw fakeroot dpkg-deb -b "-Z${DEB_COMPRESS}" "$@"
}

# for long-running, host-side expanded bash invocations.
# the user gets a pv-based spinner based on the number of lines that flows to stdout (log messages).
# the raw version is already redirect stderr to stdout, and we'll be running under do_with_logging,
# so: _the stdout must flow_!!!
function run_host_command_logged_long_running() {
	# @TODO: disabled. The Pipe used for "pv" causes the left-hand side to run in a subshell.
	#local _exit_code=1
	#if [[ "${SHOW_LOG}" == "yes" ]] || [[ "${CI}" == "true" ]]; then
	#	run_host_command_logged_raw /bin/bash -e -c "$*"
	#	_exit_code=$?
	#else
	#	run_host_command_logged_raw /bin/bash -e -c "$*" | pv -N "$(logging_echo_prefix_for_pv "${INDICATOR:-compile}")  " --progress --timer --line-mode --force --cursor --delay-start 0 -i "2"
	#	_exit_code=$?
	#fi
	#return $_exit_code

	# Run simple and exit with it's code. Sorry.
	run_host_command_logged_raw /bin/bash -e -c "$*"
}

# For installing packages host-side. Not chroot!
function host_apt_get_install() {
	host_apt_get --no-install-recommends install "$@"
}

# For running apt-get stuff host-side. Not chroot!
function host_apt_get() {
	local -a apt_params=("-${APT_OPTS:-y}")
	apt_params+=(-o "Dpkg::Use-Pty=0") # Please be quiet
	run_host_command_logged DEBIAN_FRONTEND=noninteractive apt-get "${apt_params[@]}" "$@"
}

# run_host_command_logged is the very basic, should be used for everything, but, please use helpers above, this is very low-level.
function run_host_command_logged() {
	run_host_command_logged_raw /bin/bash -e -c "$*"
}

# for interactive, dialog-like host-side invocations. no redirections performed, but same bash usage and expansion, for consistency.
function run_host_command_dialog() {
	/bin/bash -e -c "$*"
}

# do NOT use directly, it does NOT expand the way it should (through bash)
function run_host_command_logged_raw() {
	# Log the command to the current logfile, so it has context of what was run.
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo "       " >> "${CURRENT_LOGFILE}" # blank line for reader's benefit
		echo "-->" "$*" " <- at $(date --utc)" >> "${CURRENT_LOGFILE}"
	else
		display_alert "Command debug" "$*" "command" # A special 'command' level.
	fi

	# uncomment when desperate to understand what's going on
	# echo "cmd about to run" "$@" >&2

	# In this case I wanna KNOW exactly what failed, thus disable errexit, then re-enable immediately after running.
	set +e
	local exit_code=666
	"$@" 2>&1 # redirect stderr to stdout. $* is NOT $@!
	exit_code=$?
	set -e
	if [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo "--> cmd exited with code ${exit_code} at $(date --utc)" >> "${CURRENT_LOGFILE}"
	fi
	if [[ $exit_code != 0 ]]; then
		# This is very specific; remove CURRENT_LOGFILE's value when calling display_alert here otherwise logged twice.
		CURRENT_LOGFILE="" display_alert "cmd exited with code ${exit_code}" "$*" "wrn"
		CURRENT_LOGFILE="" display_alert "stacktrace for failed command" "$(show_caller_full)" "wrn"
	fi
	return $exit_code
}

# @TODO: logging: used by desktop.sh exclusively. let's unify?
run_on_sdcard() {
	chroot_sdcard "${@}"
}

# For host-side invocations of binaries we _know_ are x86-only.
# Determine if we're building on non-amd64, and if so, which qemu binary to use.
function run_host_x86_binary_logged() {
	local -a qemu_invocation target_bin_arch
	target_bin_arch="unknown - file util missing"
	if [[ -f /usr/bin/file ]]; then
		target_bin_arch="$(file -b "$1" | cut -d "," -f 1,2 | xargs echo -n)" # obtain the ELF name from the binary using 'file'
	fi
	qemu_invocation=("$@")                   # Default to calling directly, without qemu.
	if [[ "$(uname -m)" != "x86_64" ]]; then # If we're NOT on x86...
		if [[ -f /usr/bin/qemu-x86_64-static ]]; then
			display_alert "Using qemu-x86_64-static for running on $(uname -m)" "$1 (${target_bin_arch})" "debug"
			qemu_invocation=("/usr/bin/qemu-x86_64-static" "-L" "/usr/x86_64-linux-gnu" "$@")
		elif [[ -f /usr/bin/qemu-x86_64 ]]; then
			display_alert "Using qemu-x86_64 (non-static) for running on $(uname -m)" "$1 (${target_bin_arch})" "debug"
			qemu_invocation=("/usr/bin/qemu-x86_64" "-L" "/usr/x86_64-linux-gnu" "$@")
		else
			exit_with_error "Can't find appropriate qemu binary for running '$1' on $(uname -m), missing packages?"
		fi
	else
		display_alert "Not using qemu for running x86 binary on $(uname -m)" "$1 (${target_bin_arch})" "debug"
	fi
	run_host_command_logged "${qemu_invocation[@]}" # Exit with this result code
}
