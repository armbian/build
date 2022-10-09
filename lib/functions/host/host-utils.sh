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
