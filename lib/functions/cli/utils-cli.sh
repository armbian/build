#!/usr/bin/env bash

# Misc functions from compile.sh

function handle_docker_vagrant() {
	# Check for Vagrant
	if [[ "${1}" == vagrant && -z "$(command -v vagrant)" ]]; then
		display_alert "Vagrant not installed." "Installing"
		sudo apt-get update
		sudo apt-get install -y vagrant virtualbox
	fi

	# Install Docker if not there but wanted. We cover only Debian based distro install. On other distros, manual Docker install is needed
	if [[ "${1}" == docker && -f /etc/debian_version && -z "$(command -v docker)" ]]; then
		DOCKER_BINARY="docker-ce"

		# add exception for Ubuntu Focal until Docker provides dedicated binary
		codename=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d"=" -f2)
		codeid=$(cat /etc/os-release | grep ^NAME | cut -d"=" -f2 | awk '{print tolower($0)}' | tr -d '"' | awk '{print $1}')
		[[ "${codename}" == "debbie" ]] && codename="buster" && codeid="debian"
		[[ "${codename}" == "ulyana" || "${codename}" == "jammy" || "${codename}" == "kinetic" || "${codename}" == "lunar" ]] && codename="focal" && codeid="ubuntu"

		# different binaries for some. TBD. Need to check for all others
		[[ "${codename}" =~ focal|hirsute ]] && DOCKER_BINARY="docker containerd docker.io"

		display_alert "Docker not installed." "Installing" "Info"
		sudo bash -c "echo \"deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/${codeid} ${codename} stable\" > /etc/apt/sources.list.d/docker.list"

		sudo bash -c "curl -fsSL \"https://download.docker.com/linux/${codeid}/gpg\" | apt-key add -qq - > /dev/null 2>&1 "
		export DEBIAN_FRONTEND=noninteractive
		sudo apt-get update
		sudo apt-get install -y -qq --no-install-recommends ${DOCKER_BINARY}
		display_alert "Add yourself to docker group to avoid root privileges" "" "wrn"
		"${SRC}/compile.sh" "$@"
		exit $?
	fi

}

function prepare_userpatches() {
	# Create userpatches directory if not exists
	mkdir -p "${SRC}"/userpatches

	# Create example configs if none found in userpatches
	if ! ls "${SRC}"/userpatches/{config-default.conf,config-docker.conf,config-vagrant.conf} 1> /dev/null 2>&1; then

		# Migrate old configs
		if ls "${SRC}"/*.conf 1> /dev/null 2>&1; then
			display_alert "Migrate config files to userpatches directory" "all *.conf" "info"
			cp "${SRC}"/*.conf "${SRC}"/userpatches || exit 1
			rm "${SRC}"/*.conf
			[[ ! -L "${SRC}"/userpatches/config-example.conf ]] && ln -fs config-example.conf "${SRC}"/userpatches/config-default.conf || exit 1
		fi

		display_alert "Create example config file using template" "config-default.conf" "info"

		# Create example config
		if [[ ! -f "${SRC}"/userpatches/config-example.conf ]]; then
			cp "${SRC}"/config/templates/config-example.conf "${SRC}"/userpatches/config-example.conf || exit 1
		fi

		# Link default config to example config
		if [[ ! -f "${SRC}"/userpatches/config-default.conf ]]; then
			ln -fs config-example.conf "${SRC}"/userpatches/config-default.conf || exit 1
		fi

		# Create Docker config
		if [[ ! -f "${SRC}"/userpatches/config-docker.conf ]]; then
			cp "${SRC}"/config/templates/config-docker.conf "${SRC}"/userpatches/config-docker.conf || exit 1
		fi

		# Create Docker file
		if [[ ! -f "${SRC}"/userpatches/Dockerfile ]]; then
			cp "${SRC}"/config/templates/Dockerfile "${SRC}"/userpatches/Dockerfile || exit 1
		fi

		# Create Vagrant config
		if [[ ! -f "${SRC}"/userpatches/config-vagrant.conf ]]; then
			cp "${SRC}"/config/templates/config-vagrant.conf "${SRC}"/userpatches/config-vagrant.conf || exit 1
		fi

		# Create Vagrant file
		if [[ ! -f "${SRC}"/userpatches/Vagrantfile ]]; then
			cp "${SRC}"/config/templates/Vagrantfile "${SRC}"/userpatches/Vagrantfile || exit 1
		fi
	fi
}
