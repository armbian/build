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
