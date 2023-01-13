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
	)
	return 0
}

# call: prepare_python_and_pip # this defines global PYTHON3_INFO dict and PYTHON3_VARS array
function prepare_python_and_pip() {
	# First determine with python3 to use; requires knowing the HOSTRELEASE.
	[[ -z "${HOSTRELEASE}" ]] && exit_with_error "HOSTRELEASE is not set"

	# fake-memoize this, it's expensive and does not need to be done twice
	declare -g _already_prepared_python_and_pip="${_already_prepared_python_and_pip:-no}"
	if [[ "${_already_prepared_python_and_pip}" == "yes" ]]; then
		display_alert "All Python preparation done before" "skipping python prep" "debug"
		return 0
	fi

	declare python3_binary_path="/usr/bin/python3"
	declare python3_pip_bin_path="/usr/bin/pip3" # from hostdeps package python3-pip
	# Determine what version of python3;  focal-like OS's have Python 3.8, but we need 3.9.
	if [[ "focal ulyana ulyssa uma una" == *"$HOSTRELEASE"* ]]; then
		python3_binary_path="/usr/bin/python3.9"
		display_alert "Using  '${python3_binary_path}' for" "'$HOSTRELEASE' has outdated python3, using python3.9" "warn"
	fi

	# Check that the actual python3 --version is 3.9 at least
	declare python3_version
	python3_version="$("${python3_binary_path}" --version 2>&1 | cut -d' ' -f2)"
	display_alert "Python3 version" "${python3_version}" "info"
	if ! linux-version compare "${python3_version}" ge "3.9"; then
		exit_with_error "Python3 version is too old (${python3_version}), need at least 3.9"
	fi

	# Check actual pip3 version
	declare pip3_version
	pip3_version="$("${python3_binary_path}" "${python3_pip_bin_path}" --version 2>&1 | cut -d' ' -f2)"
	display_alert "pip3 version" "${pip3_version}" "info"

	# Hash the contents of the dependencies array + the Python version + the release
	declare python3_pip_dependencies_hash
	early_prepare_pip3_dependencies_for_python_tools
	python3_pip_dependencies_hash="$(echo "${HOSTRELEASE}" "${python3_version}" "${python3_pip_dependencies[*]}" | sha256sum | cut -d' ' -f1)"

	declare python_pip_cache="${SRC}/cache/pip"
	declare python_hash_base="${python_pip_cache}/pip_pkg_hash"
	declare python_hash_file="${python_hash_base}_${python3_pip_dependencies_hash}"
	declare python3_user_base="${SRC}/cache/pip/base"
	declare python3_pycache="${SRC}/cache/pip/pycache"

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
		display_alert "Using cached pip packages for Python tools" "${python3_pip_dependencies_hash}" "cachehit"
	else
		display_alert "Installing pip packages for Python tools" "${python3_pip_dependencies_hash:0:10}" "info"
		# remove the old hashes matching base, don't leave junk behind
		run_host_command_logged rm -fv "${python_hash_base}*"

		# @TODO: when running with sudo:
		# WARNING: The directory '/home/human/.cache/pip' or its parent directory is not owned or is not writable by the current user. The cache has been disabled. Check the permissions and owner of that directory. If executing pip with sudo, you should use sudo's -H flag.
		# --root-user-action=ignore requires pip 22.1+

		run_host_command_logged env -i "${PYTHON3_VARS[@]@Q}" "${PYTHON3_INFO[BIN]}" "${python3_pip_bin_path}" install \
			--no-warn-script-location --user "${python3_pip_dependencies[@]}"

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
