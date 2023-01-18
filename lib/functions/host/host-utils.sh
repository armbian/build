#!/usr/bin/env bash

function fetch_and_build_host_tools() {
	call_extension_method "fetch_sources_tools" <<- 'FETCH_SOURCES_TOOLS'
		*fetch host-side sources needed for tools and build*
		Run early to fetch_from_repo or otherwise obtain sources for needed tools.
	FETCH_SOURCES_TOOLS

	call_extension_method "build_host_tools" <<- 'BUILD_HOST_TOOLS'
		*build needed tools for the build, host-side*
		After sources are fetched, build host-side tools needed for the build.
	BUILD_HOST_TOOLS

}

# wait_for_package_manager
#
# * installation will break if we try to install when package manager is running
#
wait_for_package_manager() {
	# exit if package manager is running in the back
	while true; do
		if [[ "$(
			fuser /var/lib/dpkg/lock 2> /dev/null
			echo $?
		)" != 1 && "$(
			fuser /var/lib/dpkg/lock-frontend 2> /dev/null
			echo $?
		)" != 1 ]]; then
			display_alert "Package manager is running in the background." "Please wait! Retrying in 30 sec" "wrn"
			sleep 30
		else
			break
		fi
	done
}

# Install the whitespace-delimited packages listed in the first parameter, in the host (not chroot).
# It handles correctly the case where all wanted packages are already installed, and in that case does nothing.
# If packages are to be installed, it does an apt-get update first.
function install_host_side_packages() {
	declare wanted_packages_string PKG_TO_INSTALL
	declare -a currently_installed_packages
	declare -a missing_packages
	declare -a currently_provided_packages
	wanted_packages_string=${*}
	missing_packages=()

	# We need to jump through hoops to get the installed packages, due to the fact the "Provided" packages are a bit hidden.
	# Case in point: "gcc-aarch64-linux-gnu" is provided by "gcc" on native iron
	# If we don't do this, we keep on trying to apt install something that's already installed.

	# shellcheck disable=SC2207 # I wanna split, thanks.
	currently_installed_packages=($(dpkg-query --show --showformat='${Package} '))
	# shellcheck disable=SC2207 # I wanna split, thanks.
	currently_provided_packages=($(dpkg-query --show --showformat='${Provides}\n' | grep -v "^$" | sed -e 's/([^()]*)//g' | sed -e 's|,||g' | tr -s "\n" " "))

	for PKG_TO_INSTALL in ${wanted_packages_string}; do
		# shellcheck disable=SC2076 # I wanna match literally, thanks.
		if [[ ! " ${currently_installed_packages[*]} " =~ " ${PKG_TO_INSTALL} " ]]; then
			if [[ ! " ${currently_provided_packages[*]} " =~ " ${PKG_TO_INSTALL} " ]]; then
				missing_packages+=("${PKG_TO_INSTALL}")
			fi
		fi
	done

	unset currently_installed_packages
	unset currently_provided_packages

	if [[ ${#missing_packages[@]} -gt 0 ]]; then
		display_alert "Updating apt host-side for installing host-side packages" "${#missing_packages[@]} packages" "info"
		host_apt_get update
		display_alert "Installing host-side packages" "${missing_packages[*]}" "info"
		host_apt_get_install "${missing_packages[@]}" || exit_with_error "Failed to install host packages; make sure you have a sane sources.list."
	else
		display_alert "All host-side dependencies/packages already installed." "Skipping host-hide install" "debug"
	fi

	return 0
}

function is_root_or_sudo_prefix() {
	declare -n __my_sudo_prefix=${1} # nameref...
	if [[ "${EUID}" == "0" ]]; then
		# do not use sudo if we're effectively already root
		display_alert "EUID=0, so" "we're already root!" "debug"
		__my_sudo_prefix=""
	elif [[ -n "$(command -v sudo)" ]]; then
		# sudo binary found in path, use it.
		display_alert "EUID is not 0" "sudo binary found, using it" "debug"
		__my_sudo_prefix="sudo"
	else
		# No root and no sudo binary. Bail out
		exit_with_error "EUID is not 0 and no sudo binary found - Please install sudo or run as root"
	fi
	return 0
}

# Usage: local_apt_deb_cache_prepare variable_for_use_yes_no variable_for_cache_dir "when you are using cache/before doing XX/after YY"
function local_apt_deb_cache_prepare() {
	declare -n __my_use_yes_or_no=${1}      # nameref...
	declare -n __my_apt_cache_host_dir=${2} # nameref...
	declare when_used="${3}"

	__my_use_yes_or_no="no"
	if [[ "${USE_LOCAL_APT_DEB_CACHE}" != "yes" ]]; then
		# Not using the local cache, do nothing. Just return "no" in the first nameref.
		return 0
	fi

	__my_use_yes_or_no="yes"
	__my_apt_cache_host_dir="${SRC}/cache/aptcache/${RELEASE}-${ARCH}"
	mkdir -p "${__my_apt_cache_host_dir}" "${__my_apt_cache_host_dir}/archives"

	# get the size, in bytes, of the cache directory, including subdirs
	declare -i cache_size # heh, mark var as integer
	cache_size=$(du -sb "${__my_apt_cache_host_dir}" | cut -f1)

	display_alert "Size of apt/deb cache ${when_used}" "${cache_size} bytes" "debug"

	declare -g -i __previous_apt_cache_size
	if [[ -z "${__previous_apt_cache_size}" ]]; then
		# first time, set the size to 0
		__previous_apt_cache_size=0
	else
		# not first time, check if the size has changed
		if [[ "${cache_size}" -ne "${__previous_apt_cache_size}" ]]; then
			display_alert "Local apt cache size changed ${when_used}" "from ${__previous_apt_cache_size} to ${cache_size} bytes" "debug"
		else
			display_alert "Local apt cache size unchanged ${when_used}" "at ${cache_size} bytes" "debug"
		fi
	fi
	__previous_apt_cache_size=${cache_size}

	return 0
}

# usage: if armbian_is_host_running_systemd; then ... fi
function armbian_is_host_running_systemd() {
	# Detect if systemctl is available in the path
	if [[ -n "$(command -v systemctl)" ]]; then
		display_alert "systemctl binary found" "host has systemd installed" "debug"
		# Detect if systemd is actively running
		if systemctl is-system-running --quiet; then
			display_alert "systemctl reports" "systemd is running" "debug"
			return 0
		else
			display_alert "systemctl binary found" "but systemd is not running" "debug"
			return 1
		fi
	else
		display_alert "systemctl binary not found" "host does not have systemd installed" "debug"
	fi

	# Not running with systemd, return 1.
	display_alert "Systemd not detected" "host is not running systemd" "debug"
	return 1
}

# usage: if armbian_is_running_in_container; then ... fi
function armbian_is_running_in_container() {
	# First, check an environment variable. This is passed by the docker launchers, and also set in the Dockerfile, so should be authoritative.
	if [[ "${ARMBIAN_RUNNING_IN_CONTAINER}" == "yes" ]]; then
		display_alert "ARMBIAN_RUNNING_IN_CONTAINER is set to 'yes' in the environment" "so we're running in a container/Docker" "debug"
		return 0
	fi

	# Second, check the hardcoded path `/.dockerenv` -- not all Docker images have this, but if they do, we're pretty sure it is under Docker.
	if [[ -f "/.dockerenv" ]]; then
		display_alert "File /.dockerenv exists" "so we're running in a container/Docker" "debug"
		return 0
	fi

	# Third: if host is actively running systemd (not just installed), it's very _unlikely_ that we're running under Docker. bail.
	if armbian_is_host_running_systemd; then
		display_alert "Host is running systemd" "so we're not running in a container/Docker" "debug"
		return 1
	fi

	# Fourth, if `systemd-detect-virt` is available in the path, and executing it returns "docker", we're pretty sure it is under Docker.
	if [[ -n "$(command -v systemd-detect-virt)" ]]; then
		local systemd_detect_virt_output
		systemd_detect_virt_output="$(systemd-detect-virt)"
		if [[ "${systemd_detect_virt_output}" == "docker" ]]; then
			display_alert "systemd-detect-virt says we're running in a container/Docker" "so we're running in a container/Docker" "debug"
			return 0
		else
			display_alert "systemd-detect-virt says we're running on '${systemd_detect_virt_output}'" "so we're not running in a container/Docker" "debug"
		fi
	fi

	# End of the line. I've nothing else to check here. We're not running in a container/Docker.
	display_alert "No evidence found that we're running in a container/Docker" "so we're not running in a container/Docker" "debug"
	return 1
}

# This does `mkdir -p` on the parameters, and also sets it to be owned by the correct UID.
# Call: armbian_mkdir_p_and_chown_to_user "dir1" "dir2" "dir3/dir4"
function mkdir_recursive_and_set_uid_owner() {
	# loop over args...
	for dir in "$@"; do
		mkdir -p "${dir}"
		reset_uid_owner "${dir}"
	done
}

# Call: reset_uid_owner "one/file" "some/directory" "another/file" - is recursive if dir given
function reset_uid_owner() {
	if [[ "x${SET_OWNER_TO_UID}x" == "xx" ]]; then
		return 0 # Nothing to do.
	fi
	# Loop over args..
	local arg
	for arg in "$@"; do
		display_alert "reset_uid_owner: '${arg}' will be owner id '${SET_OWNER_TO_UID}'" "reset_uid_owner" "debug"
		if [[ -d "${arg}" ]]; then
			chown "${SET_OWNER_TO_UID}" "${arg}"
			find "${arg}" -uid 0 -print0 | xargs --no-run-if-empty -0 chown "${SET_OWNER_TO_UID}"
		elif [[ -f "${arg}" ]]; then
			chown "${SET_OWNER_TO_UID}" "${arg}"
		else
			display_alert "reset_uid_owner: '${arg}' is not a file or directory" "skipping" "debug"
			return 1
		fi
	done
}

# Non recursive version of the above
function reset_uid_owner_non_recursive() {
	if [[ "x${SET_OWNER_TO_UID}x" == "xx" ]]; then
		return 0 # Nothing to do.
	fi
	# Loop over args..
	local arg
	for arg in "$@"; do
		display_alert "reset_uid_owner_non_recursive: '${arg}' will be owner id '${SET_OWNER_TO_UID}'" "reset_uid_owner_non_recursive" "debug"
		if [[ -d "${arg}" ]]; then
			chown "${SET_OWNER_TO_UID}" "${arg}"
		elif [[ -f "${arg}" ]]; then
			chown "${SET_OWNER_TO_UID}" "${arg}"
		else
			display_alert "reset_uid_owner_non_recursive: '${arg}' is not a file or directory" "skipping" "debug"
			return 1
		fi
	done
}

# call: check_dir_for_mount_options "/path/to/dir" "main build dir description"
function check_dir_for_mount_options() {
	declare -r dir="${1}"
	declare -r description="${2}"

	declare src_mount_source="" src_mount_opts=""
	src_mount_opts="$(findmnt -T "${dir}" --output OPTIONS --raw --notruncate --noheadings)"

	# make sure $src_mount_opts does not contain noexec
	if [[ "${src_mount_opts}" == *"noexec"* || "${src_mount_opts}" == *"nodev"* ]]; then
		src_mount_source="$(findmnt -T "${dir}" --output SOURCE --raw --notruncate --noheadings)"
		display_alert "Directory ${dir} (${description}) is mounted" "from '${src_mount_source}' with options '${src_mount_opts}'" "warn"
		exit_with_error "Directory ${dir} (${description}) is mounted with the 'noexec' and/or 'nodev' options; this will cause rootfs build failures. Please correct this before trying again."
	fi

	display_alert "Checked directory OK for mount options" "${dir} ('${description}')" "info"

	return 0
}

function trap_handler_reset_output_owner() {
	display_alert "Resetting output directory owner" "${SRC}/output" "debug"
	reset_uid_owner "${SRC}/output"
	# For .tmp: do NOT do it recursively. If another build is running in another process, this is destructive if recursive.
	display_alert "Resetting tmp directory owner" "${SRC}/.tmp" "debug"
	reset_uid_owner_non_recursive "${SRC}/.tmp"
}

# Recursive function to find all descendant processes of a given PID. Writes to stdout.
function list_descendants_of_pid() {
	local children
	children=$(ps -o "pid=" --ppid "$1" | xargs echo -n)

	for pid in $children; do
		list_descendants_of_pid "$pid"
	done

	echo -n "${children} "
}

function get_descendants_of_pid_array() {
	local descendants
	descendants="$(list_descendants_of_pid "$1")"
	display_alert "Descendants of PID $1: ${descendants}" "string - get_descendants_of_pid_array" "debug"
	# shellcheck disable=SC2206 # lets expand!
	descendants_of_pid_array_result=(${descendants})
	display_alert "Descendants of PID $1: ${descendants_of_pid_array_result[*]}" "array = get_descendants_of_pid_array" "debug"
}
