function obtain_and_check_hostrelease() {
	# obtain the host release either from os-release or debian_version
	declare -g HOSTRELEASE
	HOSTRELEASE="$(cat /etc/os-release | grep VERSION_CODENAME | cut -d"=" -f2)"
	[[ -z $HOSTRELEASE ]] && HOSTRELEASE="$(cut -d'/' -f1 /etc/debian_version)"
	display_alert "Build host OS release" "${HOSTRELEASE:-(unknown)}" "info"

	# Ubuntu Jammy x86_64 or arm64 is the only fully supported host OS release
	# Using Docker/VirtualBox is the only supported way to run the build script on other Linux distributions
	#
	# NO_HOST_RELEASE_CHECK overrides the check for a supported host system
	# Disable host OS check at your own risk. Any issues reported with unsupported releases will be closed without discussion
	if [[ -z $HOSTRELEASE || "bullseye bookworm sid focal impish hirsute jammy kinetic lunar ulyana ulyssa uma una vanessa vera" != *"$HOSTRELEASE"* ]]; then
		if [[ $NO_HOST_RELEASE_CHECK == yes ]]; then
			display_alert "You are running on an unsupported system" "${HOSTRELEASE:-(unknown)}" "wrn"
			display_alert "Do not report any errors, warnings or other issues encountered beyond this point" "" "wrn"
		else
			exit_with_error "Unsupported build system: '${HOSTRELEASE:-(unknown)}'"
		fi
	fi
}
