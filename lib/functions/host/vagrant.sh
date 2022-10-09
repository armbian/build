# @TODO: called by no-one, yet, or ever. This should not be done here.
function vagrant_install_vagrant() {
	# Check for Vagrant
	# @TODO yeah, checks for ${1} in a function. not cool. not the place to install stuff either.
	if [[ "${1}" == vagrant && -z "$(command -v vagrant)" ]]; then
		display_alert "Vagrant not installed." "Installing"
		sudo apt-get update
		sudo apt-get install -y vagrant virtualbox
	fi
}

function vagrant_prepare_userpatches() {
	# Create example configs if none found in userpatches
	if [[ ! -f "${SRC}"/userpatches/config-vagrant.conf ]]; then
		display_alert "Create example Vagrant config using template" "config-vagrant.conf" "info"

		# Create Vagrant config
		if [[ ! -f "${SRC}"/userpatches/config-vagrant.conf ]]; then
			cp "${SRC}"/config/templates/config-vagrant.conf "${SRC}"/userpatches/config-vagrant.conf || exit 1
		fi
	fi
	if [[ ! -f "${SRC}"/userpatches/Vagrantfile ]]; then

		# Create Vagrant file
		if [[ ! -f "${SRC}"/userpatches/Vagrantfile ]]; then
			cp "${SRC}"/config/templates/Vagrantfile "${SRC}"/userpatches/Vagrantfile || exit 1
		fi
	fi

}
