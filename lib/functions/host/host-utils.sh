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
	declare wanted_packages_string
	declare -a currently_installed_packages missing_packages
	wanted_packages_string=${*}
	missing_packages=()
	# shellcheck disable=SC2207 # I wanna split, thanks.
	currently_installed_packages=($(dpkg-query --show --showformat='${Package} '))
	for PKG_TO_INSTALL in ${wanted_packages_string}; do
		# shellcheck disable=SC2076 # I wanna match literally, thanks.
		if [[ ! " ${currently_installed_packages[*]} " =~ " ${PKG_TO_INSTALL} " ]]; then
			display_alert "Should install package" "${PKG_TO_INSTALL}"
			missing_packages+=("${PKG_TO_INSTALL}")
		fi
	done

	if [[ ${#missing_packages[@]} -gt 0 ]]; then
		display_alert "Updating apt host-side for installing packages" "${#missing_packages[@]} packages" "info"
		host_apt_get update
		display_alert "Installing host-side packages" "${missing_packages[*]}" "info"
		host_apt_get_install "${missing_packages[@]}"
	else
		display_alert "All host-side dependencies/packages already installed." "Skipping host-hide install" "debug"
	fi

	unset currently_installed_packages
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
