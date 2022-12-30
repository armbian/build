#!/usr/bin/env bash
#  Add the variables needed at the beginning of the path
check_args() {

	for p in "$@"; do

		case "${p%=*}" in
			LIB_TAG)
				# Take a variable if the branch exists locally
				if [ "${p#*=}" == "$(git branch |
					gawk -v b="${p#*=}" '{if ( $NF == b ) {print $NF}}')" ]; then
					echo -e "[\e[0;35m warn \x1B[0m] Setting $p"
					eval "$p"
				else
					echo -e "[\e[0;35m warn \x1B[0m] Skip $p setting as LIB_TAG=\"\""
					eval LIB_TAG=""
				fi
				;;
		esac

	done

}

update_src() {

	cd "${SRC}" || exit
	if [[ ! -f "${SRC}"/.ignore_changes ]]; then
		echo -e "[\e[0;32m o.k. \x1B[0m] This script will try to update"

		CHANGED_FILES=$(git diff --name-only)
		if [[ -n "${CHANGED_FILES}" ]]; then
			echo -e "[\e[0;35m warn \x1B[0m] Can't update since you made changes to: \e[0;32m\n${CHANGED_FILES}\x1B[0m"
			while true; do
				echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m or \e[0;33mexit\x1B[0m to abort compilation" \
					", \e[0;33m<Enter>\x1B[0m to ignore and continue, \e[0;33mdiff\x1B[0m to display changes"
				read -r
				if [[ "${REPLY}" == "diff" ]]; then
					git diff
				elif [[ "${REPLY}" == "exit" ]]; then
					exit 1
				elif [[ "${REPLY}" == "" ]]; then
					break
				else
					echo "Unknown command!"
				fi
			done
		elif [[ $(git branch | grep "*" | awk '{print $2}') != "${LIB_TAG}" && -n "${LIB_TAG}" ]]; then
			git checkout "${LIB_TAG:-master}"
			git pull
		fi
	fi

}

function do_update_src() {
	TMPFILE=$(mktemp)
	chmod 644 "${TMPFILE}"
	{

		echo SRC="$SRC"
		echo LIB_TAG="$LIB_TAG"
		declare -f update_src
		echo "update_src"

	} > "$TMPFILE"

	#do not update/checkout git with root privileges to messup files onwership.
	#due to in docker/VM, we can't su to a normal user, so do not update/checkout git.
	if [[ $(systemd-detect-virt) == 'none' ]]; then

		if [[ "${EUID}" == "0" ]]; then
			su "$(stat --format=%U "${SRC}"/.git)" -c "bash ${TMPFILE}"
		else
			bash "${TMPFILE}"
		fi

	fi

	rm "${TMPFILE}"
}

function handle_vagrant() {
	# Check for Vagrant
	if [[ "${1}" == vagrant && -z "$(command -v vagrant)" ]]; then
		display_alert "Vagrant not installed." "Installing"
		sudo apt-get update
		sudo apt-get install -y vagrant virtualbox
	fi
}

function handle_docker() {
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
