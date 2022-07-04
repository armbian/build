function extension_prepare_config__prepare_localmodconfig() {
	# If defined, ${KERNEL_CONFIG_FROM_LSMOD} can contain a lsmod to apply to the kernel configuration.
	# to get a file for this run 'lsmod > my_machine.lsmod' and then put it in userpatches/lsmod/
	export KERNEL_CONFIG_FROM_LSMOD="${KERNEL_CONFIG_FROM_LSMOD:-}"
	display_alert "localmodconfig INIT lsmod" "${KERNEL_CONFIG_FROM_LSMOD}" "warn"

	# If there, make sure it exists
	local lsmod_file="${SRC}/userpatches/lsmod/${KERNEL_CONFIG_FROM_LSMOD}.lsmod"
	if [[ ! -f "${lsmod_file}" ]]; then
		exit_with_error "Can't find lsmod file ${lsmod_file}, configure with KERNEL_CONFIG_FROM_LSMOD=xxx"
	fi
}

# This needs much more love than this. can be used to make "light" versions of kernels, that compile 3x-5x faster or more
function custom_kernel_config_post_defconfig__apply_localmodconfig() {
	display_alert "localmodconfig with lsmod" "${KERNEL_CONFIG_FROM_LSMOD}" "warn"
	if [[ "a${KERNEL_CONFIG_FROM_LSMOD}a" != "aa" ]]; then
		local lsmod_file="${SRC}/userpatches/lsmod/${KERNEL_CONFIG_FROM_LSMOD}.lsmod"
		run_kernel_make "LSMOD=${lsmod_file}" localmodconfig
		kernel_config_mtime=$(get_file_modification_time ".config") # capture the mtime of the config file after the localmodconfig
	fi
}
