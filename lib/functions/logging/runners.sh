#!/usr/bin/env bash

# shortcut
function chroot_sdcard_apt_get_install() {
	chroot_sdcard_apt_get --no-install-recommends install "$@"
}

function chroot_sdcard_apt_get_install_download_only() {
	chroot_sdcard_apt_get --no-install-recommends --download-only install "$@"
}

function chroot_sdcard_apt_get_install_dry_run() {
	chroot_sdcard_apt_get --no-install-recommends --dry-run install "$@"
}

function chroot_sdcard_apt_get_remove() {
	DONT_MAINTAIN_APT_CACHE="yes" chroot_sdcard_apt_get remove "$@"
}

function chroot_sdcard_apt_get() {
	acng_check_status_or_restart # make sure apt-cacher-ng is running OK.

	local -a apt_params=("-y")
	if [[ "${MANAGE_ACNG}" == "yes" ]]; then
		display_alert "Using managed apt-cacher-ng" "http://localhost:3142" "debug"
		apt_params+=(
			-o "Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-"localhost:3142"}\""
			-o "Acquire::http::Proxy::localhost=\"DIRECT\""
		)
	elif [[ -n "${APT_PROXY_ADDR}" ]]; then
		display_alert "Using unmanaged apt mirror" "http://${APT_PROXY_ADDR}" "debug"
		apt_params+=(
			-o "Acquire::http::Proxy=\"http://${APT_PROXY_ADDR}\""
			-o "Acquire::http::Proxy::localhost=\"DIRECT\""
		)
	else
		display_alert "Not using apt-cacher-ng, nor proxy" "no proxy/acng" "debug"
	fi

	apt_params+=(-o "Dpkg::Use-Pty=0") # Please be quiet

	if [[ "${DONT_MAINTAIN_APT_CACHE:-no}" == "yes" ]]; then
		# Configure Clean-Installed to off
		display_alert "Configuring APT to not clean up the cache" "APT will not clean up the cache" "debug"
		apt_params+=(-o "APT::Clean-Installed=0")
	fi

	# Allow for clean-environment apt-get
	local -a prelude_clean_env=()
	if [[ "${use_clean_environment:-no}" == "yes" ]]; then
		display_alert "Running with clean environment" "$*" "debug"
		prelude_clean_env=("env" "-i")
	fi

	local use_local_apt_cache apt_cache_host_dir
	local_apt_deb_cache_prepare use_local_apt_cache apt_cache_host_dir "before 'apt-get $*'" # 2 namerefs + "when"
	if [[ "${use_local_apt_cache}" == "yes" ]]; then
		# prepare and mount apt cache dir at /var/cache/apt/archives in the SDCARD.
		local apt_cache_sdcard_dir="${SDCARD}/var/cache/apt"
		run_host_command_logged mkdir -pv "${apt_cache_sdcard_dir}"
		display_alert "Mounting local apt cache dir" "${apt_cache_sdcard_dir}" "debug"
		run_host_command_logged mount --bind "${apt_cache_host_dir}" "${apt_cache_sdcard_dir}"
	fi

	local chroot_apt_result=1
	chroot_sdcard "${prelude_clean_env[@]}" DEBIAN_FRONTEND=noninteractive apt-get "${apt_params[@]}" "$@" && chroot_apt_result=0

	local_apt_deb_cache_prepare use_local_apt_cache apt_cache_host_dir "after 'apt-get $*'" # 2 namerefs + "when"
	if [[ "${use_local_apt_cache}" == "yes" ]]; then
		display_alert "Unmounting apt cache dir" "${apt_cache_sdcard_dir}" "debug"
		run_host_command_logged umount "${apt_cache_sdcard_dir}"
	fi

	return $chroot_apt_result
}

# please, please, unify around this function.
function chroot_sdcard() {
	TMPDIR="" run_host_command_logged_raw chroot "${SDCARD}" /bin/bash -e -o pipefail -c "$*"
}

# please, please, unify around this function.
function chroot_mount() {
	TMPDIR="" run_host_command_logged_raw chroot "${MOUNT}" /bin/bash -e -o pipefail -c "$*"
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
	# 	TMPDIR="" run_host_command_logged_raw chroot "${target}" /bin/bash -e -o pipefail -c "$*"
	# 	_exit_code=$?
	# else
	# 	TMPDIR="" run_host_command_logged_raw chroot "${target}" /bin/bash -e -o pipefail -c "$*" | pv -N "$(logging_echo_prefix_for_pv "${INDICATOR:-compile}")" --progress --timer --line-mode --force --cursor --delay-start 0 -i "0.5"
	# 	_exit_code=$?
	# fi
	# return $_exit_code

	TMPDIR="" run_host_command_logged_raw chroot "${target}" /bin/bash -e -o pipefail -c "$*"
}

function chroot_custom() {
	local target=$1
	shift
	TMPDIR="" run_host_command_logged_raw chroot "${target}" /bin/bash -e -o pipefail -c "$*"
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
	#	run_host_command_logged_raw /bin/bash -e -o pipefail-c "$*"
	#	_exit_code=$?
	#else
	#	run_host_command_logged_raw /bin/bash -e -o pipefail -c "$*" | pv -N "$(logging_echo_prefix_for_pv "${INDICATOR:-compile}")  " --progress --timer --line-mode --force --cursor --delay-start 0 -i "2"
	#	_exit_code=$?
	#fi
	#return $_exit_code

	# Run simple and exit with it's code. Sorry.
	run_host_command_logged_raw /bin/bash -e -o pipefail -c "$*"
}

# For installing packages host-side. Not chroot!
function host_apt_get_install() {
	host_apt_get --no-install-recommends install "$@"
}

# For running apt-get stuff host-side. Not chroot!
function host_apt_get() {
	local -a apt_params=("-y")
	apt_params+=(-o "Dpkg::Use-Pty=0") # Please be quiet
	run_host_command_logged DEBIAN_FRONTEND=noninteractive apt-get "${apt_params[@]}" "$@"
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

# run_host_command_logged is the very basic, should be used for everything, but, please use helpers above, this is very low-level.
function run_host_command_logged() {
	run_host_command_logged_raw /bin/bash -e -o pipefail -c "$*"
}

# for interactive, dialog-like host-side invocations. no redirections performed, but same bash usage and expansion, for consistency.
function run_host_command_dialog() {
	/bin/bash -e -o pipefail -c "$*"
}

# do NOT use directly, it does NOT expand the way it should (through bash)
function run_host_command_logged_raw() {
	# Log the command to the current logfile, so it has context of what was run.
	display_alert "Command debug" "$*" "command" # A special 'command' level.

	# In this case I wanna KNOW exactly what failed, thus disable errexit, then re-enable immediately after running.
	set +e
	local exit_code=666
	local seconds_start=${SECONDS} # Bash has a builtin SECONDS that is seconds since start of script
	"$@" 2>&1                      # redirect stderr to stdout. $* is NOT $@!
	exit_code=$?
	set -e

	if [[ ${exit_code} != 0 ]]; then
		if [[ -f "${CURRENT_LOGFILE}" ]]; then
			echo "-->--> command failed with error code ${exit_code} after $((SECONDS - seconds_start)) seconds" >> "${CURRENT_LOGFILE}"
		fi
		# This is very specific; remove CURRENT_LOGFILE's value when calling display_alert here otherwise logged twice.
		CURRENT_LOGFILE="" display_alert "cmd exited with code ${exit_code}" "$*" "wrn"
		CURRENT_LOGFILE="" display_alert "stacktrace for failed command" "$(show_caller_full)" "wrn"

		# Obtain extra info about error, eg, log files produced, extra messages set by caller, etc.
		logging_enrich_run_command_error_info

	elif [[ -f "${CURRENT_LOGFILE}" ]]; then
		echo "-->--> command run successfully after $((SECONDS - seconds_start)) seconds" >> "${CURRENT_LOGFILE}"
	fi

	logging_clear_run_command_error_info # clear the error info vars, always, otherwise they'll leak into the next invocation.

	return ${exit_code} #  exiting with the same error code as the original error
}

function logging_clear_run_command_error_info() {
	# Unset those globals; they're only valid for the first invocation of a runner helper function after they're set.
	unset if_error_detail_message
	unset if_error_find_files_sdcard # remember, this is global.
}

function logging_enrich_run_command_error_info() {
	declare -a found_files=()

	for path in "${if_error_find_files_sdcard[@]}"; do
		declare -a sdcard_files
		# shellcheck disable=SC2086 # I wanna expand, thank you...
		mapfile -t sdcard_files < <(find ${SDCARD}/${path} -type f)
		display_alert "Found if_error_find_files_sdcard files" "${sdcard_files[@]}" "debug"
		found_files+=("${sdcard_files[@]}") # add to result
	done

	for found_file in "${found_files[@]}"; do
		# Log to asset, so it's available in the HTML log
		LOG_ASSET="chroot_error_context__$(basename "${found_file}")" do_with_log_asset cat "${found_file}"

		display_alert "File contents for error context" "${found_file}" "err"
		# shellcheck disable=SC2002 # cat is not useless, ccze _only_ takes stdin
		cat "${found_file}" | ccze -A 1>&2 # to stderr
		# @TODO: 3x repeated ccze invocation, lets refactor it later
	done

	### if_error_detail_message, array: messages to display if the command failed.
	if [[ -n ${if_error_detail_message} ]]; then
		display_alert "Error context msg" "${if_error_detail_message}" "err"
	fi
}

# @TODO: logging: used by desktop.sh exclusively. let's unify?
run_on_sdcard() {
	chroot_sdcard "${@}"
}
