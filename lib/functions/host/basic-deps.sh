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
		"linux-version:linux-base"
		"locale-gen:locales"
		"systemd-detect-virt:systemd" # @TODO: rpardini: we really docker-detect-virt that much?
		"git:git"
	)

	for check_pack in "${checklist[@]}"; do
		if ! which ${check_pack%:*} > /dev/null; then local install_pack+=${check_pack#*:}" "; fi
	done

	if [[ -n $install_pack ]]; then
		local sudo_prefix="" && is_root_or_sudo_prefix sudo_prefix # nameref; "sudo_prefix" will be 'sudo' or ''
		display_alert "Installing basic packages" "${sudo_prefix}: ${install_pack}"
		run_host_command_logged "${sudo_prefix}" apt-get -qq update
		run_host_command_logged "${sudo_prefix}" apt-get install -qq -y --no-install-recommends $install_pack
	else
		display_alert "basic-deps are already installed" "nothing to be done" "debug"
	fi

}
