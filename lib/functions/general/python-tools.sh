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

function early_prepare_pip3_dependencies_for_python_tools() {
	# This is like a stupid version of requirements.txt
	declare -a -g python3_pip_dependencies=(
		"unidiff==0.7.4"      # for parsing unified diff
		"GitPython==3.1.30"   # for manipulating git repos
		"unidecode==1.3.6"    # for converting strings to ascii
		"coloredlogs==15.0.1" # for colored logging
		"PyYAML==6.0"         # for parsing/writing YAML
		"oras==0.1.17"        # for OCI stuff in mapper-oci-update
		"Jinja2==3.1.2"       # for templating
		"rich==13.4.1"        # for rich text formatting
	)
	return 0
}

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
	declare python3_version python3_full_version
	python3_full_version="$("${python3_binary_path}" --version)" # "cut" below masks errors, do it twice.
	python3_version="$("${python3_binary_path}" --version | cut -d' ' -f2)"
	display_alert "Python3 version" "${python3_version} - '${python3_full_version}'" "info"
	if ! linux-version compare "${python3_version}" ge "3.9"; then
		exit_with_error "Python3 version is too old (${python3_version}), need at least 3.9"
	fi

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
	declare python3_pip_dependencies_hash
	early_prepare_pip3_dependencies_for_python_tools
	python3_pip_dependencies_hash="$(echo "${HOSTRELEASE}" "${python3_version}" "${pip3_version}" "${python3_pip_dependencies[*]}" | sha256sum | cut -d' ' -f1)"

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
	declare python3_pycache="${python_pip_cache}/pycache"

	# declare a readonly global dict with all needed info for executing stuff using this setup
	declare -r -g -A PYTHON3_INFO=(
		[BIN]="${python3_binary_path}"
		[USERBASE]="${python3_user_base}"
		[PYCACHEPREFIX]="${python3_pycache}"
		[HASH]="${python3_pip_dependencies_hash}"
		[DEPS]="${python3_pip_dependencies[*]}"
		[VERSION]="${python3_version}"
		[PIP_VERSION]="${pip3_version}"
	)

	# declare a readonly global array for ENV vars to invoke python3 with
	declare -r -g -a PYTHON3_VARS=(
		"PYTHONUSERBASE=${PYTHON3_INFO[USERBASE]}"
		"PYTHONUNBUFFERED=yes"
		"PYTHONPYCACHEPREFIX=${PYTHON3_INFO[PYCACHEPREFIX]}"
	)

	# If the hash file exists, we're done.
	if [[ -f "${python_hash_file}" ]]; then
		display_alert "Using cached pip packages for Python tools" "${python3_pip_dependencies_hash}" "info"
	else
		display_alert "Installing pip packages for Python tools" "${python3_pip_dependencies_hash:0:10}" "info"
		# remove the old hashes matching base, don't leave junk behind
		run_host_command_logged rm -fv "${python_hash_base}*"

		run_host_command_logged env -i "${PYTHON3_VARS[@]@Q}" "${PYTHON3_INFO[BIN]}" -m pip install "${pip3_extra_args[@]}" "${python3_pip_dependencies[@]}"

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
