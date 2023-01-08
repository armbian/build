function kernel_config_maybe_interactive() {
	# Check if we're gonna do some interactive configuration; if so, don't run kernel_config under logging manager.
	if [[ $KERNEL_CONFIGURE != yes ]]; then
		LOG_SECTION="kernel_config" do_with_logging do_with_hooks kernel_config
	else
		LOG_SECTION="kernel_config_interactive" do_with_hooks kernel_config
	fi
}

function kernel_config() {
	# re-read kernel version after patching
	version=$(grab_version "$kernel_work_dir")

	display_alert "Compiling $BRANCH kernel" "$version" "info"

	# compare with the architecture of the current Debian node
	# if it matches we use the system compiler
	if dpkg-architecture -e "${ARCH}"; then
		display_alert "Native compilation" "target ${ARCH} on host $(dpkg --print-architecture)"
	else
		display_alert "Cross compilation" "target ${ARCH} on host $(dpkg --print-architecture)"
		toolchain=$(find_toolchain "$KERNEL_COMPILER" "$KERNEL_USE_GCC")
		[[ -z $toolchain ]] && exit_with_error "Could not find required toolchain" "${KERNEL_COMPILER}gcc $KERNEL_USE_GCC"
	fi

	kernel_compiler_version="$(eval env PATH="${toolchain}:${PATH}" "${KERNEL_COMPILER}gcc" -dumpfullversion -dumpversion)"
	display_alert "Compiler version" "${KERNEL_COMPILER}gcc ${kernel_compiler_version}" "info"

	# copy kernel config
	local COPY_CONFIG_BACK_TO=""

	if [[ $KERNEL_KEEP_CONFIG == yes && -f "${DEST}"/config/$LINUXCONFIG.config ]]; then
		display_alert "Using previous kernel config" "${DEST}/config/$LINUXCONFIG.config" "info"
		run_host_command_logged cp -pv "${DEST}/config/${LINUXCONFIG}.config" .config
	else
		# @TODO: rpardini: this is too contrived, make obvious, use an array and a loop and stop repeating itself
		if [[ -f $USERPATCHES_PATH/$LINUXCONFIG.config ]]; then
			display_alert "Using kernel config provided by user" "userpatches/$LINUXCONFIG.config" "info"
			run_host_command_logged cp -pv "${USERPATCHES_PATH}/${LINUXCONFIG}.config" .config
			COPY_CONFIG_BACK_TO="${USERPATCHES_PATH}/${LINUXCONFIG}.config"
		elif [[ -f "${USERPATCHES_PATH}/config/kernel/${LINUXCONFIG}.config" ]]; then
			display_alert "Using kernel config provided by user in config/kernel folder" "config/kernel/${LINUXCONFIG}.config" "info"
			run_host_command_logged cp -pv "${USERPATCHES_PATH}/config/kernel/${LINUXCONFIG}.config" .config
			COPY_CONFIG_BACK_TO="${USERPATCHES_PATH}/config/kernel/${LINUXCONFIG}.config"
		else
			display_alert "Using kernel config file" "config/kernel/$LINUXCONFIG.config" "info"
			run_host_command_logged cp -pv "${SRC}/config/kernel/${LINUXCONFIG}.config" .config
			COPY_CONFIG_BACK_TO="${SRC}/config/kernel/${LINUXCONFIG}.config"
		fi
	fi

	# Store the .config modification date at this time, for restoring later. Otherwise rebuilds.
	local kernel_config_mtime
	kernel_config_mtime=$(get_file_modification_time ".config")

	call_extension_method "custom_kernel_config" <<- 'CUSTOM_KERNEL_CONFIG'
		*Kernel .config is in place, still clean from git version*
		Called after ${LINUXCONFIG}.config is put in place (.config).
		Before any olddefconfig any Kconfig make is called.
		A good place to customize the .config directly.
	CUSTOM_KERNEL_CONFIG

	# hack for OdroidXU4. Copy firmare files
	if [[ $BOARD == odroidxu4 ]]; then
		mkdir -p "${kernel_work_dir}/firmware/edid"
		cp -p "${SRC}"/packages/blobs/odroidxu4/*.bin "${kernel_work_dir}/firmware/edid"
	fi

	display_alert "Kernel configuration" "${LINUXCONFIG}" "info"

	if [[ $KERNEL_CONFIGURE != yes ]]; then
		run_kernel_make olddefconfig # @TODO: what is this? does it fuck up dates?
	else
		display_alert "Starting (non-interactive) kernel olddefconfig" "${LINUXCONFIG}" "debug"

		run_kernel_make olddefconfig

		# No logging for this. this is UI piece
		display_alert "Starting (interactive) kernel ${KERNEL_MENUCONFIG:-menuconfig}" "${LINUXCONFIG}" "debug"
		run_kernel_make_dialog "${KERNEL_MENUCONFIG:-menuconfig}"

		# Capture new date. Otherwise changes not detected by make.
		kernel_config_mtime=$(get_file_modification_time ".config")

		# store kernel config in easily reachable place
		mkdir -p "${DEST}"/config
		display_alert "Exporting new kernel config" "$DEST/config/$LINUXCONFIG.config" "info"
		run_host_command_logged cp -pv .config "${DEST}/config/${LINUXCONFIG}.config"

		# store back into original LINUXCONFIG too, if it came from there, so it's pending commits when done.
		if [[ "${COPY_CONFIG_BACK_TO}" != "" ]]; then
			display_alert "Exporting new kernel config - git commit pending" "${COPY_CONFIG_BACK_TO}" "info"
			run_host_command_logged cp -pv .config "${COPY_CONFIG_BACK_TO}"

			# export defconfig
			run_kernel_make savedefconfig
			run_host_command_logged cp -pv defconfig "${DEST}/config/${LINUXCONFIG}.defconfig"
			run_host_command_logged cp -pv defconfig "${COPY_CONFIG_BACK_TO}.defconfig"
		fi
	fi

	call_extension_method "custom_kernel_config_post_defconfig" <<- 'CUSTOM_KERNEL_CONFIG_POST_DEFCONFIG'
		*Kernel .config is in place, already processed by Armbian*
		Called after ${LINUXCONFIG}.config is put in place (.config).
		After all olddefconfig any Kconfig make is called.
		A good place to customize the .config last-minute.
	CUSTOM_KERNEL_CONFIG_POST_DEFCONFIG

	# Restore the date of .config. Above delta is a pure function, theoretically.
	set_files_modification_time "${kernel_config_mtime}" ".config"
}
