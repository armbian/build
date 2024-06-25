#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# This whole thing is a big "I refuse to use venv in a simple bash script" delusion.
# If you know to tame it, teach me. I'd rather not know about PYTHONUSERBASE and such.
# --rpardini

# call: prepare_python_and_pip # this defines global PYTHON3_INFO dict and PYTHON3_VARS array
function prepare_python_and_pip() {
	assert_prepared_host # this needs a prepared host to work; avoid fake errors about "python3-pip" not being installed
	# First determine with python3 to use; requires knowing the HOSTRELEASE.
	[[ -z "${HOSTRELEASE}" ]] && exit_with_error "HOSTRELEASE is not set"

	# fake-memoize this, it's expensive and does not need to be done twice
	declare -g _already_prepared_python_and_pip="${_already_prepared_python_and_pip:-no}"
	if [[ "${_already_prepared_python_and_pip}" == "yes" ]]; then
		display_alert "All Python preparation done before" "skipping python prep" "debug"
		return 0
	fi

	declare python3_binary_path="/usr/bin/python3"
	# Determine what version of python3;  focal-like OS's have Python 3.8, but we need 3.9.
	if [[ "focal ulyana ulyssa uma una" == *"$HOSTRELEASE"* ]]; then
		python3_binary_path="/usr/bin/python3.9"
		display_alert "Using  '${python3_binary_path}' for" "'$HOSTRELEASE' has outdated python3, using python3.9" "warn"
	fi

	# Check that the actual python3 --version is 3.9 at least
	declare python3_version python3_version_full
	python3_version_full="$("${python3_binary_path}" --version)" # "cut" below masks errors, do it twice.
	python3_version="$("${python3_binary_path}" --version | cut -d' ' -f2)"
	display_alert "Python3 version" "${python3_version} - '${python3_version_full}'" "info"
	if ! linux-version compare "${python3_version}" ge "3.9"; then
		exit_with_error "Python3 version is too old (${python3_version}), need at least 3.9"
	fi

	declare python3_version_majorminor python3_version_string
	# Extract the major and minor version numbers (e.g., "3.12" instead of "3.12.2")
	python3_version_majorminor=$(echo "${python3_version_full}" | awk '{print $2}' | cut -d. -f1,2)
	# Construct the version string (e.g., "python3.12")
	python3_version_string="python$python3_version_majorminor"

	# Check actual pip3 version
	#   Note: we don't use "/usr/bin/pip3" at all, since it's commonly missing. instead "python -m pip"
	#   The hostdep package python3-pip is still required, and other crazy might impact this.
	#   We might need to install our own pip if it gets bad enough.
	declare pip3_version
	pip3_version="$("${python3_binary_path}" -m pip --version)"

	# get the pip3 version number only (eg, "21.2.4" from "pip 21.2.4 from /usr/lib/python3/dist-packages/pip (python 3.9)")
	declare pip3_version_number
	pip3_version_number="$(echo "${pip3_version}" | cut -d' ' -f2)" # @TODO: brittle. how to do this better?
	display_alert "pip3 version" "${pip3_version_number}: '${pip3_version}'" "info"

	# Hash the contents of the dependencies array + the Python version + the release
	declare python3_pip_dependencies_path
	declare python3_pip_dependencies_hash

	python3_pip_dependencies_path="${SRC}/requirements.txt"
	# Check for the existence of requirements.txt, fail if not found
	[[ ! -f "${python3_pip_dependencies_path}" ]] && exit_with_error "Python Pip requirements.txt file not found at path: ${python3_pip_dependencies_path}"

	# Calculate the hash for the Pip requirements
	python3_pip_dependencies_hash="$(echo "${HOSTRELEASE}" "${python3_version}" "${pip3_version}" "$(cat "${python3_pip_dependencies_path}")" | sha256sum | cut -d' ' -f1)"

	declare non_cache_dir="/armbian-pip"
	declare python_pip_cache="${SRC}/cache/pip"

	if [[ "${deploy_to_non_cache_dir:-"no"}" == "yes" ]]; then
		display_alert "Using non-cache dir" "PIP: ${non_cache_dir}" "warn"
		python_pip_cache="${non_cache_dir}"
	else
		# if the non-cache dir exists, copy it into place, if not already existing...
		if [[ -d "${non_cache_dir}" && ! -d "${python_pip_cache}" ]]; then
			display_alert "Deploying pip cache from Docker image" "${non_cache_dir} -> ${python_pip_cache}" "info"
			run_host_command_logged cp -pr "${non_cache_dir}" "${python_pip_cache}"
		fi
	fi

	declare -a pip3_extra_args=("--no-warn-script-location" "--user")
	# if pip 23+, add "--break-system-packages" to pip3 invocations.
	# See See PEP 668 -- System-wide package management with pip
	# but the fact is that we're _not_ managing system-wide, instead --user
	if linux-version compare "${pip3_version_number}" ge "23.0"; then
		pip3_extra_args+=("--break-system-packages")
	fi
	if linux-version compare "${pip3_version_number}" ge "22.1"; then
		pip3_extra_args+=("--root-user-action=ignore")
	fi

	declare python_hash_base="${python_pip_cache}/pip_pkg_hash"
	declare python_hash_file="${python_hash_base}_${python3_pip_dependencies_hash}"
	declare python3_user_base="${python_pip_cache}/base"
	declare python3_modules_path="${python3_user_base}/lib/${python3_version_string}/site-packages"
	declare python3_pycache="${python_pip_cache}/pycache"

	# declare a readonly global dict with all needed info for executing stuff using this setup
	declare -r -g -A PYTHON3_INFO=(
		[BIN]="${python3_binary_path}"
		[USERBASE]="${python3_user_base}"
		[MODULES_PATH]="${python3_modules_path}"
		[PYCACHEPREFIX]="${python3_pycache}"
		[REQUIREMENTS_HASH]="${python3_pip_dependencies_hash}"
		[REQUIREMENTS_PATH]="${python3_pip_dependencies_path}"
		[VERSION]="${python3_version}"
		[VERSION_STRING]="${python3_version_string}"
		[PIP_VERSION]="${pip3_version}"
	)

	# declare a readonly global array for ENV vars to invoke python3 with
	declare -r -g -a PYTHON3_VARS=(
		"PYTHONUSERBASE=${PYTHON3_INFO[USERBASE]}"
		"PYTHONUNBUFFERED=yes"
		"PYTHONPYCACHEPREFIX=${PYTHON3_INFO[PYCACHEPREFIX]}"
		"PATH=\"${toolchain}:${PYTHON3_INFO[USERBASE]}/bin:${PATH}\"" # add toolchain to PATH to make building wheels work
	)

	# If the hash file exists, we're done.
	if [[ -f "${python_hash_file}" ]]; then
		display_alert "Using cached pip packages for Python tools" "${python3_pip_dependencies_hash}" "info"
	else
		display_alert "Installing pip packages for Python tools" "${python3_pip_dependencies_hash:0:10}" "info"
		# remove the old hashes matching base, don't leave junk behind
		run_host_command_logged rm -fv "${python_hash_base}*"

		run_host_command_logged env -i "${PYTHON3_VARS[@]@Q}" "${PYTHON3_INFO[BIN]}" -m pip install "${pip3_extra_args[@]}" -r "${python3_pip_dependencies_path}"

		# Create the hash file
		run_host_command_logged touch "${python_hash_file}"
	fi

	_already_prepared_python_and_pip="yes"
	return 0
}

# Called during early_prepare_host_dependencies(); when building a Dockerfile, host_release is set to the Docker image name.
function host_deps_add_extra_python() {
	# check host_release is set, or bail.
	[[ -z "${host_release}" ]] && exit_with_error "host_release is not set"

	# host_release is from outer scope (
	# Determine what version of python3;  focal-like OS's have Python 3.8, but we need 3.9.
	if [[ "focal ulyana ulyssa uma una" == *"${host_release}"* ]]; then
		display_alert "Using Python 3.9 for" "hostdeps: '${host_release}' has outdated python3, using python3.9" "warn"
		host_dependencies+=("python3.9-dev")
	else
		display_alert "Using Python3 for" "hostdeps: '${host_release}' has python3 >= 3.9" "debug"
	fi
}
