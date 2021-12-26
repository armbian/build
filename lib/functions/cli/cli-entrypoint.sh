function cli_entrypoint() {
	if [[ "${ARMBIAN_ENABLE_CALL_TRACING}" == "yes" ]]; then
		set -T # inherit return/debug traps
		mkdir -p "${SRC}"/output/debug
		echo -n "" > "${SRC}"/output/debug/calls.txt
		trap 'echo "${BASH_LINENO[@]}|${BASH_SOURCE[@]}|${FUNCNAME[@]}" >> ${SRC}/output/debug/calls.txt ;' RETURN
	fi

	logging_init #  initialize logging.

	check_args "$@"
	do_update_src "$@"

	if [[ "${EUID}" == "0" ]] || [[ "${1}" == "vagrant" ]]; then
		:
	elif [[ "${1}" == docker || "${1}" == dockerpurge || "${1}" == docker-shell ]] && grep -q "$(whoami)" <(getent group docker); then
		:
	else
		display_alert "This script requires root privileges, trying to use sudo" "" "wrn"
		sudo "${SRC}/compile.sh" "$@"
		exit $?
	fi

	# The only way to get this is via ENV var...
	if [ "$OFFLINE_WORK" == "yes" ]; then
		echo -e "\n"
		display_alert "* " "You are working offline."
		display_alert "* " "Sources, time and host will not be checked"
		echo -e "\n"
		sleep 3s
	else
		# check and install the basic utilities here # @TODO: logging?
		prepare_host_basic
	fi

	# Purge Armbian Docker images
	if [[ "${1}" == dockerpurge && -f /etc/debian_version ]]; then
		display_alert "Purging Armbian Docker containers" "" "wrn"
		docker container ls -a | grep armbian | awk '{print $1}' | xargs docker container rm &> /dev/null
		docker image ls | grep armbian | awk '{print $3}' | xargs docker image rm &> /dev/null
		shift
		set -- "docker" "$@"
	fi

	# Docker shell
	if [[ "${1}" == docker-shell ]]; then
		shift
		#shellcheck disable=SC2034
		SHELL_ONLY=yes
		set -- "docker" "$@"
	fi

	handle_docker_vagrant "$@"

	prepare_userpatches "$@"

	if [[ -z "${CONFIG}" && -n "$1" && -f "${SRC}/userpatches/config-$1.conf" ]]; then
		CONFIG="userpatches/config-$1.conf"
		shift
	fi

	# using default if custom not found
	if [[ -z "${CONFIG}" && -f "${SRC}/userpatches/config-default.conf" ]]; then
		CONFIG="userpatches/config-default.conf"
	fi

	# source build configuration file
	CONFIG_FILE="$(realpath "${CONFIG}")"

	if [[ ! -f "${CONFIG_FILE}" ]]; then
		display_alert "Config file does not exist" "${CONFIG}" "error"
		exit 254
	fi

	CONFIG_PATH=$(dirname "${CONFIG_FILE}")

	# Source the extensions manager library at this point, before sourcing the config.
	# This allows early calls to enable_extension(), but initialization proper is done later.
	# shellcheck source=lib/extensions.sh
	source "${SRC}"/lib/extensions.sh

	display_alert "Using config file" "${CONFIG_FILE}" "info"
	pushd "${CONFIG_PATH}" > /dev/null || exit
	# shellcheck source=/dev/null
	source "${CONFIG_FILE}"
	popd > /dev/null || exit

	[[ -z "${USERPATCHES_PATH}" ]] && USERPATCHES_PATH="${CONFIG_PATH}"

	# Script parameters handling
	while [[ "${1}" == *=* ]]; do
		parameter=${1%%=*}
		value=${1##*=}
		shift
		display_alert "Command line: setting $parameter to" "${value:-(empty)}" "info"
		eval "$parameter=\"$value\""
	done

	##
	## Main entrypoint.
	##

	# reset completely after sourcing config file
	set -e          # disallow errors
	set -o errtrace # error trace

	if [[ "${BUILD_ALL}" == "yes" || "${BUILD_ALL}" == "demo" ]]; then
		do_main_build_all_ng
	else
		# configuration etc
		do_capturing_defs prepare_and_config_main_build_single # this sets CAPTURED_VARS

		if [[ "${CONFIG_DEFS_ONLY}" == "yes" ]]; then
			echo "${CAPTURED_VARS}" # to stdout!
			return 0
		else
			unset CAPTURED_VARS
		fi

		# Allow for custom user-invoked functions. @TODO: check this with extensions usage?
		if [[ -z $1 ]]; then
			main_default_build_single
		else
			eval "$@"
		fi
	fi
}
