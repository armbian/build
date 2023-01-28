function main_default_build_packages() {
	# early cleaning for sources, since fetch_and_build_host_tools() uses it.
	if [[ "${CLEAN_LEVEL}" == *sources* ]]; then
		LOG_SECTION="cleaning_early_sources" do_with_logging general_cleaning "sources"
	fi

	# Too many things being done. Allow doing only one thing. For core development, mostly.
	# Also because "KERNEL_ONLY=yes" should really be spelled "PACKAGES_ONLY=yes"
	local do_build_uboot="yes" do_build_kernel="yes" exit_after_kernel_build="no" exit_after_uboot_build="no" do_host_tools="yes"
	if [[ "${JUST_UBOOT}" == "yes" && "${JUST_KERNEL}" == "yes" ]]; then
		exit_with_error "User of build system" "can't make up his mind about JUST_KERNEL or JUST_UBOOT"
	elif [[ "${JUST_UBOOT}" == "yes" ]]; then
		display_alert "JUST_KERNEL set to yes" "Building only kernel and exiting after that" "debug"
		do_build_uboot="yes"
		do_host_tools="${INSTALL_HOST_TOOLS:-yes}" # rkbin, fips, etc.
		exit_after_uboot_build="yes"
	elif [[ "${JUST_KERNEL}" == "yes" ]]; then
		display_alert "JUST_KERNEL set to yes" "Building only kernel and exiting after that" "debug"
		do_build_uboot="no"
		exit_after_kernel_build="yes"
		do_host_tools="no"
	fi

	# ignore updates help on building all images - for internal purposes
	if [[ "${IGNORE_UPDATES}" != "yes" ]]; then

		# Fetch and build the host tools (via extensions)
		if [[ "${do_host_tools}" == "yes" ]]; then
			LOG_SECTION="fetch_and_build_host_tools" do_with_logging fetch_and_build_host_tools
		fi

		LOG_SECTION="clean_deprecated_mountpoints" do_with_logging clean_deprecated_mountpoints

		for cleaning_fragment in $(tr ',' ' ' <<< "${CLEAN_LEVEL}"); do
			if [[ $cleaning_fragment != sources ]] && [[ $cleaning_fragment != none ]] && [[ $cleaning_fragment != make* ]]; then
				LOG_SECTION="cleaning_${cleaning_fragment}" do_with_logging general_cleaning "${cleaning_fragment}"
			fi
		done
	fi

	# Prepare ccache, cthreads, etc for the build
	LOG_SECTION="prepare_compilation_vars" do_with_logging prepare_compilation_vars

	if [[ "${do_build_uboot}" == "yes" ]]; then
		# Don't build u-boot at all if the BOOTCONFIG is 'none'.
		if [[ "${BOOTCONFIG}" != "none" ]]; then
			# @TODO: refactor this. we use it very often
			# Compile u-boot if packed .deb does not exist or use the one from repository
			if [[ ! -f "${DEB_STORAGE}"/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb || "${UBOOT_IGNORE_DEB}" == "yes" ]]; then
				if [[ -n "${ATFSOURCE}" && "${ATFSOURCE}" != "none" && "${REPOSITORY_INSTALL}" != *u-boot* ]]; then
					LOG_SECTION="compile_atf" do_with_logging compile_atf
				fi
				# @TODO: refactor this construct. we use it too many times.
				if [[ "${REPOSITORY_INSTALL}" != *u-boot* || "${UBOOT_IGNORE_DEB}" == "yes" ]]; then
					declare uboot_git_revision="not_determined_yet"
					LOG_SECTION="uboot_prepare_git" do_with_logging_unless_user_terminal uboot_prepare_git
					LOG_SECTION="compile_uboot" do_with_logging compile_uboot
				fi
			fi
		fi
		if [[ "${exit_after_uboot_build}" == "yes" ]]; then
			display_alert "Exiting after u-boot build" "JUST_UBOOT=yes" "info"
			exit 0
		fi
	fi

	# Compile kernel if packed .deb does not exist or use the one from repository
	if [[ "${do_build_kernel}" == "yes" ]]; then
		if [[ ! -f ${DEB_STORAGE}/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb || "${KERNEL_IGNORE_DEB}" == "yes" ]]; then
			if [[ -n $KERNELSOURCE ]] && [[ "${REPOSITORY_INSTALL}" != *kernel* ]]; then
				compile_kernel # This handles its own logging sections.
			fi
		fi
		if [[ "${exit_after_kernel_build}" == "yes" ]]; then
			display_alert "Only building kernel and exiting" "JUST_KERNEL=yes" "debug"
			exit 0
		fi
	fi

	# Compile armbian-config if packed .deb does not exist or use the one from repository
	if [[ ! -f ${DEB_STORAGE}/armbian-config_${REVISION}_all.deb ]]; then
		if [[ "${REPOSITORY_INSTALL}" != *armbian-config* ]]; then
			LOG_SECTION="compile_armbian-config" do_with_logging compile_armbian-config
		fi
	fi

	# Compile armbian-zsh if packed .deb does not exist or use the one from repository
	if [[ ! -f ${DEB_STORAGE}/armbian-zsh_${REVISION}_all.deb ]]; then
		if [[ "${REPOSITORY_INSTALL}" != *armbian-zsh* ]]; then
			LOG_SECTION="compile_armbian-zsh" do_with_logging compile_armbian-zsh
		fi
	fi

	# Compile plymouth-theme-armbian if packed .deb does not exist or use the one from repository
	if [[ ! -f ${DEB_STORAGE}/plymouth-theme-armbian_${REVISION}_all.deb ]]; then
		if [[ "${REPOSITORY_INSTALL}" != *plymouth-theme-armbian* ]]; then
			LOG_SECTION="compile_plymouth_theme_armbian" do_with_logging compile_plymouth_theme_armbian
		fi
	fi

	# Compile armbian-firmware if packed .deb does not exist or use the one from repository
	if ! ls "${DEB_STORAGE}/armbian-firmware_${REVISION}_all.deb" 1> /dev/null 2>&1 || ! ls "${DEB_STORAGE}/armbian-firmware-full_${REVISION}_all.deb" 1> /dev/null 2>&1; then
		if [[ "${REPOSITORY_INSTALL}" != *armbian-firmware* ]]; then
			compile_firmware_light_and_possibly_full # this has its own logging sections
		fi
	fi

	overlayfs_wrapper "cleanup"

	# Further packages require aggregation (BSPs use aggregated stuff, etc)
	assert_requires_aggregation # Bombs if aggregation has not run

	# create board support package
	if [[ -n "${RELEASE}" && ! -f "${DEB_STORAGE}/${BSP_CLI_PACKAGE_FULLNAME}.deb" && "${REPOSITORY_INSTALL}" != *armbian-bsp-cli* ]]; then
		LOG_SECTION="create_board_package" do_with_logging create_board_package
	fi

	# create desktop package
	if [[ -n "${RELEASE}" && "${DESKTOP_ENVIRONMENT}" && ! -f "${DEB_STORAGE}/$RELEASE/${CHOSEN_DESKTOP}_${REVISION}_all.deb" && "${REPOSITORY_INSTALL}" != *armbian-desktop* ]]; then
		LOG_SECTION="create_desktop_package" do_with_logging create_desktop_package
	fi
	if [[ -n "${RELEASE}" && "${DESKTOP_ENVIRONMENT}" && ! -f "${DEB_STORAGE}/${RELEASE}/${BSP_DESKTOP_PACKAGE_FULLNAME}.deb" && "${REPOSITORY_INSTALL}" != *armbian-bsp-desktop* ]]; then
		LOG_SECTION="create_bsp_desktop_package" do_with_logging create_bsp_desktop_package
	fi

	# Reset owner of DEB_STORAGE, if needed. Might be a lot of packages there, but such is life.
	# @TODO: might be needed also during 'cleanup': if some package fails, the previous package might be left owned by root.
	reset_uid_owner "${DEB_STORAGE}"

	# end of kernel-only, so display what was built.
	if [[ "${KERNEL_ONLY}" != "yes" ]]; then
		display_alert "Kernel build done" "@host" "target-reached"
		display_alert "Target directory" "${DEB_STORAGE}/" "info"
		display_alert "File name" "${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb" "info"
	fi

	# At this point, the WORKDIR should be clean. Add debug info.
	debug_tmpfs_show_usage "AFTER ALL PKGS BUILT"
}
