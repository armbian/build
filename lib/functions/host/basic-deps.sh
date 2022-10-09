#!/usr/bin/env bash
# prepare_host_basic
#
# * installs only basic packages
#
prepare_host_basic() {

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
	)

	for check_pack in "${checklist[@]}"; do
		if ! which ${check_pack%:*} > /dev/null; then local install_pack+=${check_pack#*:}" "; fi
	done

	if [[ -n $install_pack ]]; then
		display_alert "Updating and installing basic packages on host" "$install_pack"
		run_host_command_logged sudo apt-get -qq update
		run_host_command_logged sudo apt-get install -qq -y --no-install-recommends $install_pack
	fi

}
