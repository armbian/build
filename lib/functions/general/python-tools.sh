function early_prepare_pip3_dependencies_for_python_tools() {
	declare -a -g python3_pip_dependencies=(
		"unidiff==0.7.4"      # for parsing unified diff
		"GitPython==3.1.29"   # for manipulating git repos
		"unidecode==1.3.6"    # for converting strings to ascii
		"coloredlogs==15.0.1" # for colored logging
	)
	return 0
}

function prepare_pip_packages_for_python_tools() {
	early_prepare_pip3_dependencies_for_python_tools

	declare -g PYTHON_TOOLS_PIP_PACKAGES_DONE="${PYTHON_TOOLS_PIP_PACKAGES_DONE:-no}"
	if [[ "${PYTHON_TOOLS_PIP_PACKAGES_DONE}" == "yes" ]]; then
		display_alert "Required Python packages" "already installed" "info"
		return 0
	fi

	# @TODO: virtualenv? system-wide for now
	display_alert "Installing required Python packages" "via pip3" "info"
	run_host_command_logged pip3 install "${python3_pip_dependencies[@]}"

	return 0
}

# Called during early_prepare_host_dependencies(); when building a Dockerfile, HOSTRELEASE is set to the Docker image name.
function host_deps_add_extra_python() {
	# Determine what version of python3;  focal-like OS's have Python 3.8, but we need 3.9.
	if [[ "focal ulyana ulyssa uma una" == *"$HOSTRELEASE"* ]]; then
		display_alert "Using Python 3.9 for" "'$HOSTRELEASE' has outdated python3, using python3.9" "warn"
		host_dependencies+=("python3.9-dev" "python3.9-distutils")
	else
		display_alert "Using Python3 for" "'$HOSTRELEASE' has python3 >= 3.9" "debug"
	fi
}

# This sets the outer scope variable 'python3_binary_path' to /usr/bin/python3 or similar, depending on version.
function prepare_python3_binary_for_python_tools() {
	python3_binary_path="/usr/bin/python3"
	# Determine what version of python3;  focal-like OS's have Python 3.8, but we need 3.9.
	if [[ "focal ulyana ulyssa uma una" == *"$HOSTRELEASE"* ]]; then
		python3_binary_path="/usr/bin/python3.9"
		display_alert "Using  '${python3_binary_path}' for" "'$HOSTRELEASE' has outdated python3, using python3.9" "warn"
	else
		display_alert "Using '${python3_binary_path}' for" "'$HOSTRELEASE' has python3 >= 3.9" "debug"
	fi
}
