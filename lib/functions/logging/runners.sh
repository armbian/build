#!/usr/bin/env bash

# All those runner helper functions have a particular non-quoting style.
# callers might need to force quote with bash's @Q modifier.

# shortcut
function chroot_sdcard_apt_get_install() {
	chroot_sdcard_apt_get --no-install-recommends install "$@"
}

function chroot_sdcard_apt_get_install_download_only() {
	chroot_sdcard_apt_get --no-install-recommends --download-only install "$@"
}

function chroot_sdcard_apt_get_install_dry_run() {
	local logging_filter=""
	if [[ "${SHOW_DEBUG}" != "yes" ]]; then
		logging_filter="2>&1 | { grep --line-buffered -v -e '^Conf ' -e '^Inst ' || true; }"
	fi
	chroot_sdcard_apt_get --no-install-recommends --dry-run install "$@" "${logging_filter}"
}

function chroot_sdcard_apt_get_update() {
	apt_logging="-q" chroot_sdcard_apt_get update
}

function chroot_sdcard_apt_get_remove() {
	DONT_MAINTAIN_APT_CACHE="yes" chroot_sdcard_apt_get remove "$@"
}

function chroot_sdcard_apt_get() {
	acng_check_status_or_restart # make sure apt-cacher-ng is running OK.

	local -a apt_params=("-y" "${apt_logging:-"-qq"}") # super quiet by default, but can be tweaked up, for update for example
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

	# --list-cleanup
	#     This option is on by default; use --no-list-cleanup to turn it off. When it is on, apt-get will
	#     automatically manage the contents of /var/lib/apt/lists to ensure that obsolete files are erased. The only
	#     reason to turn it off is if you frequently change your sources list. Configuration Item:
	#     APT::Get::List-Cleanup.
	apt_params+=(-o "APT::Get::List-Cleanup=0") # Armbian frequently changes ours sources list; it's dynamic via aggregation

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

	local_apt_deb_cache_prepare "before 'apt-get $*'" # sets LOCAL_APT_CACHE_INFO
	if [[ "${LOCAL_APT_CACHE_INFO[USE]}" == "yes" ]]; then
		# prepare and mount apt cache dir at /var/cache/apt/archives in the SDCARD.
		run_host_command_logged mkdir -pv "${LOCAL_APT_CACHE_INFO[SDCARD_DEBS_DIR]}" "${LOCAL_APT_CACHE_INFO[SDCARD_LISTS_DIR]}"
		display_alert "Mounting local apt deb cache dir" "${LOCAL_APT_CACHE_INFO[SDCARD_DEBS_DIR]}" "debug"
		run_host_command_logged mount --bind "${LOCAL_APT_CACHE_INFO[HOST_DEBS_DIR]}" "${LOCAL_APT_CACHE_INFO[SDCARD_DEBS_DIR]}"
		display_alert "Mounting local apt list cache dir" "${LOCAL_APT_CACHE_INFO[SDCARD_LISTS_DIR]}" "debug"
		run_host_command_logged mount --bind "${LOCAL_APT_CACHE_INFO[HOST_LISTS_DIR]}" "${LOCAL_APT_CACHE_INFO[SDCARD_LISTS_DIR]}"
	fi

	local chroot_apt_result=1
	chroot_sdcard "${prelude_clean_env[@]}" DEBIAN_FRONTEND=noninteractive apt-get "${apt_params[@]}" "$@" && chroot_apt_result=0

	local_apt_deb_cache_prepare "after 'apt-get $*'" # sets LOCAL_APT_CACHE_INFO
	if [[ "${LOCAL_APT_CACHE_INFO[USE]}" == "yes" ]]; then
		display_alert "Unmounting apt deb cache dir" "${LOCAL_APT_CACHE_INFO[SDCARD_DEBS_DIR]}" "debug"
		run_host_command_logged umount "${LOCAL_APT_CACHE_INFO[SDCARD_DEBS_DIR]}"
		display_alert "Unmounting apt list cache dir" "${LOCAL_APT_CACHE_INFO[SDCARD_LISTS_DIR]}" "debug"
		run_host_command_logged umount "${LOCAL_APT_CACHE_INFO[SDCARD_LISTS_DIR]}"
	fi

	return $chroot_apt_result
}

# please, please, unify around this function.
function chroot_sdcard() {
	raw_command="$*" raw_extra="chroot_sdcard" TMPDIR="" \
		run_host_command_logged_raw chroot "${SDCARD}" ${BASH:-"/usr/bin/env bash"} -e -o pipefail -c "$*"
}

# please, please, unify around this function.
function chroot_mount() {
	raw_command="$*" raw_extra="chroot_mount" TMPDIR="" \
		run_host_command_logged_raw chroot "${MOUNT}" ${BASH:-"/usr/bin/env bash"} -e -o pipefail -c "$*"
}

# This should be used if you need to capture the stdout produced by the command. It is NOT logged, and NOT run thru bash, and NOT quoted.
function chroot_sdcard_with_stdout() {
	TMPDIR="" chroot "${SDCARD}" "$@"
}

function chroot_custom_long_running() { # any pipe causes the left-hand side to subshell and caos ensues. it's just like chroot_custom()
	local target=$1
	shift
	raw_command="$*" raw_extra="chroot_custom_long_running" TMPDIR="" run_host_command_logged_raw chroot "${target}" ${BASH:-"/usr/bin/env bash"} -e -o pipefail -c "$*"
}

function chroot_custom() {
	local target=$1
	shift
	raw_command="$*" raw_extra="chroot_custom" TMPDIR="" run_host_command_logged_raw chroot "${target}" ${BASH:-"/usr/bin/env bash"} -e -o pipefail -c "$*"
}

# For installing packages host-side. Not chroot!
function host_apt_get_install() {
	host_apt_get --no-install-recommends install "$@"
}

# For running apt-get stuff host-side. Not chroot!
function host_apt_get() {
	local -a apt_params=("-y" "-qq")
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

# Run simple and exit with it's code. Exactly the same as run_host_command_logged(). Used to have pv pipe, but that causes chaos.
function run_host_command_logged_long_running() {
	raw_command="${raw_command:-"$*"}" run_host_command_logged_raw ${BASH:-"/usr/bin/env bash"} -e -o pipefail -c "$*"
}

# run_host_command_logged is the very basic, should be used for everything, but, please use helpers above, this is very low-level.
function run_host_command_logged() {
	raw_command="${raw_command:-"$*"}" run_host_command_logged_raw ${BASH:-"/usr/bin/env bash"} -e -o pipefail -c "$*"
}

# for interactive, dialog-like host-side invocations. no redirections performed, but same bash usage and expansion, for consistency.
function run_host_command_dialog() {
	${BASH:-"/usr/bin/env bash"} -e -o pipefail -c "$*"
}

# do NOT use directly, it does NOT expand the way it should (through bash)
function run_host_command_logged_raw() {
	# Log the command to the current logfile, so it has context of what was run.
	# The real command might be very long, so, if raw_command is defined, log that instead.
	display_alert "${raw_command:-"$*"}" "" "command" # A special 'command' level.

	# In this case I wanna KNOW exactly what failed, thus disable errexit, then re-enable immediately after running.
	set +e
	local exit_code=666
	local seconds_start=${SECONDS} # Bash has a builtin SECONDS that is seconds since start of script
	"$@" 2>&1                      # redirect stderr to stdout. $* is NOT $@!
	exit_code=$?
	set -e

	if [[ ${exit_code} != 0 ]]; then
		if [[ -f "${CURRENT_LOGFILE}" ]]; then # echo -e "\033[91mBright Red\033[0m"
			echo -e "${bright_red_color:-}-->--> command failed with error code ${exit_code} after $((SECONDS - seconds_start)) seconds${normal_color:-}" >> "${CURRENT_LOGFILE}"
		fi

		# @TODO: send these _ONLY_ to logfile. there's enough on screen already...
		display_alert_skip_screen=1 display_alert "stacktrace for failed command" "exit code ${exit_code}:$*\n$(stack_color="${magenta_color:-}" show_caller_full)" "wrn"

		# Obtain extra info about error, eg, log files produced, extra messages set by caller, etc.
		logging_enrich_run_command_error_info
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
		cat "${found_file}" 1>&2 # to stderr
	done

	### if_error_detail_message, array: messages to display if the command failed.
	if [[ -n ${if_error_detail_message} ]]; then
		display_alert "Error context msg" "${if_error_detail_message}" "err"
	fi
}
