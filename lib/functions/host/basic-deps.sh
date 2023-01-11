#!/usr/bin/env bash
# prepare_host_basic
#
# * installs only basic packages
#
function prepare_host_basic() {

	# command:package1 package2 ...
	# list of commands that are neeeded:packages where this command is
	local check_pack install_pack
	local checklist=(
		"dialog:dialog"
		"fuser:psmisc"
		"getfacl:acl"
		"uuidgen:uuid-runtime"
		"curl:curl"
		"gpg:gnupg"
		"gawk:gawk"
		"linux-version:linux-base"
		"locale-gen:locales"
		"git:git"
	)

	for check_pack in "${checklist[@]}"; do
		if ! which ${check_pack%:*} > /dev/null; then local install_pack+=${check_pack#*:}" "; fi
	done

	if [[ -n $install_pack ]]; then
		# This obviously only works on Debian or Ubuntu.
		if [[ ! -f /etc/debian_version ]]; then
			exit_with_error "Missing packages -- can't install basic packages on non Debian/Ubuntu"
		fi

		local sudo_prefix="" && is_root_or_sudo_prefix sudo_prefix # nameref; "sudo_prefix" will be 'sudo' or ''
		display_alert "Updating and installing basic packages on host ${sudo_prefix}" "${install_pack}"
		run_host_command_logged "${sudo_prefix}" DEBIAN_FRONTEND=noninteractive apt-get -o "Dpkg::Use-Pty=0" -q update
		run_host_command_logged "${sudo_prefix}" DEBIAN_FRONTEND=noninteractive apt-get -o "Dpkg::Use-Pty=0" install -qq -y --no-install-recommends $install_pack
	else
		display_alert "basic-deps are already installed on host" "nothing to be done" "debug"
	fi

}
