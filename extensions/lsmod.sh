function extension_prepare_config__prepare_localmodconfig() {
	# If defined, ${LSMOD} can contain a lsmod to apply to the kernel configuration.
	# to get a file for this run 'lsmod > my_machine.lsmod' and then put it in userpatches/lsmod/
	declare -g -r LSMOD="${LSMOD:-"${BOARD}"}" # default to the board name
	display_alert "${EXTENSION}: lsmod enabled" "${LSMOD}" "warn"

	# If there, make sure it exists
	declare -g -r lsmod_file="${SRC}/userpatches/lsmod/${LSMOD}.lsmod"
	if [[ ! -f "${lsmod_file}" ]]; then
		exit_with_error "Can't find lsmod file ${lsmod_file}, create it by running lsmod on target HW or configure with LSMOD=xxx"
	fi
}

# This needs much more love than this. can be used to make "light" versions of kernels, that compile 3x-5x faster or more
function custom_kernel_config__apply_localmodconfig() {
	if [[ -f "${lsmod_file}" ]]; then
		kernel_config_modifying_hashes+=("$(cat "${lsmod_file}")")
		if [[ -f .config ]]; then
			display_alert "${EXTENSION}: running localmodconfig on Kernel tree" "${LSMOD}" "warn"
			run_kernel_make "LSMOD=${lsmod_file}" localmodconfig "> /dev/null" # quoted redirect to hide output even from logfile, it's way too long. stderr still shows
		fi
	else
		display_alert "${EXTENSION}: lsmod file disappeared?" "${lsmod_file}" "err"
		return 1 # exit with an error; this is not what the user expected
	fi
}
