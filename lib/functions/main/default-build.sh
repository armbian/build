do_default() {

	start=$(date +%s)

	# Check and install dependencies, directory structure and settings
	# The OFFLINE_WORK variable inside the function
	prepare_host

	[[ "${JUST_INIT}" == "yes" ]] && exit 0

	[[ $CLEAN_LEVEL == *sources* ]] && cleaning "sources"

	# fetch_from_repo <url> <dir> <ref> <subdir_flag>

	# ignore updates help on building all images - for internal purposes
	if [[ $IGNORE_UPDATES != yes ]]; then
		display_alert "Downloading sources" "" "info"
		[[ -n $BOOTSOURCE ]] && fetch_from_repo "$BOOTSOURCE" "$BOOTDIR" "$BOOTBRANCH" "yes"
		[[ -n $ATFSOURCE ]] && fetch_from_repo "$ATFSOURCE" "$ATFDIR" "$ATFBRANCH" "yes"

		if [[ -n $KERNELSOURCE ]]; then
			if $(declare -f var_origin_kernel > /dev/null); then
				unset LINUXSOURCEDIR
				LINUXSOURCEDIR="linux-mainline/$KERNEL_VERSION_LEVEL"
				VAR_SHALLOW_ORIGINAL=var_origin_kernel
				waiter_local_git "url=$KERNELSOURCE $KERNELSOURCENAME $KERNELBRANCH dir=$LINUXSOURCEDIR $KERNELSWITCHOBJ"
				unset VAR_SHALLOW_ORIGINAL
			else
				fetch_from_repo "$KERNELSOURCE" "$KERNELDIR" "$KERNELBRANCH" "yes"
			fi
		fi

		call_extension_method "fetch_sources_tools" <<- 'FETCH_SOURCES_TOOLS'
			*fetch host-side sources needed for tools and build*
			Run early to fetch_from_repo or otherwise obtain sources for needed tools.
		FETCH_SOURCES_TOOLS

		call_extension_method "build_host_tools" <<- 'BUILD_HOST_TOOLS'
			*build needed tools for the build, host-side*
			After sources are fetched, build host-side tools needed for the build.
		BUILD_HOST_TOOLS

		for option in $(tr ',' ' ' <<< "$CLEAN_LEVEL"); do
			[[ $option != sources ]] && cleaning "$option"
		done
	fi

	# Don't build at all if the BOOTCONFIG is 'none'.
	[[ "${BOOTCONFIG}" != "none" ]] && {
		# Compile u-boot if packed .deb does not exist or use the one from repository
		if [[ ! -f "${DEB_STORAGE}"/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb ]]; then
			if [[ -n "${ATFSOURCE}" && "${REPOSITORY_INSTALL}" != *u-boot* ]]; then
				compile_atf
			fi
			[[ "${REPOSITORY_INSTALL}" != *u-boot* ]] && compile_uboot
		fi
	}

	if [[ $UBOOT_ONLY == yes ]]; then

		display_alert "U-Boot build done" "@host" "info"
		display_alert "Target directory" "${DEB_STORAGE}/" "info"
		display_alert "File name" "${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb" "info"

	else

		# Compile kernel if packed .deb does not exist or use the one from repository
		if [[ ! -f ${DEB_STORAGE}/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb ]]; then

			KDEB_CHANGELOG_DIST=$RELEASE
			[[ -n $KERNELSOURCE ]] && [[ "${REPOSITORY_INSTALL}" != *kernel* ]] && compile_kernel

		fi

		# Compile armbian-config if packed .deb does not exist or use the one from repository
		if [[ ! -f ${DEB_STORAGE}/armbian-config_${REVISION}_all.deb ]]; then

			[[ "${REPOSITORY_INSTALL}" != *armbian-config* ]] && compile_armbian-config

		fi

		# Compile armbian-zsh if packed .deb does not exist or use the one from repository
		if [[ ! -f ${DEB_STORAGE}/armbian-zsh_${REVISION}_all.deb ]]; then

			[[ "${REPOSITORY_INSTALL}" != *armbian-zsh* ]] && compile_armbian-zsh

		fi

		# Compile plymouth-theme-armbian if packed .deb does not exist or use the one from repository
		if [[ ! -f ${DEB_STORAGE}/plymouth-theme-armbian_${REVISION}_all.deb ]]; then

			[[ "${REPOSITORY_INSTALL}" != *plymouth-theme-armbian* ]] && compile_plymouth-theme-armbian

		fi

		# Compile armbian-firmware if packed .deb does not exist or use the one from repository
		if ! ls "${DEB_STORAGE}/armbian-firmware_${REVISION}_all.deb" 1> /dev/null 2>&1 || ! ls "${DEB_STORAGE}/armbian-firmware-full_${REVISION}_all.deb" 1> /dev/null 2>&1; then

			if [[ "${REPOSITORY_INSTALL}" != *armbian-firmware* ]]; then
				[[ "${INSTALL_ARMBIAN_FIRMWARE:-yes}" == "yes" ]] && { # Build firmware by default.
					FULL=""
					REPLACE="-full"
					compile_firmware
					FULL="-full"
					REPLACE=""
					compile_firmware
				}

			fi

		fi

		overlayfs_wrapper "cleanup"

		# create board support package
		[[ -n "${RELEASE}" && ! -f "${DEB_STORAGE}/${BSP_CLI_PACKAGE_FULLNAME}.deb" && "${REPOSITORY_INSTALL}" != *armbian-bsp-cli* ]] && create_board_package

		# create desktop package
		[[ -n "${RELEASE}" && "${DESKTOP_ENVIRONMENT}" && ! -f "${DEB_STORAGE}/$RELEASE/${CHOSEN_DESKTOP}_${REVISION}_all.deb" && "${REPOSITORY_INSTALL}" != *armbian-desktop* ]] && create_desktop_package
		[[ -n "${RELEASE}" && "${DESKTOP_ENVIRONMENT}" && ! -f "${DEB_STORAGE}/${RELEASE}/${BSP_DESKTOP_PACKAGE_FULLNAME}.deb" && "${REPOSITORY_INSTALL}" != *armbian-bsp-desktop* ]] && create_bsp_desktop_package

		# skip image creation if exists. useful for CI when making a lot of images
		if [ "$IMAGE_PRESENT" == yes ] && ls "${FINALDEST}/${VENDOR}_${REVISION}_${BOARD^}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}${DESKTOP_ENVIRONMENT:+_$DESKTOP_ENVIRONMENT}"*.xz 1> /dev/null 2>&1; then
			display_alert "Skipping image creation" "image already made - IMAGE_PRESENT is set" "wrn"
			exit
		fi

		# build additional packages
		[[ $EXTERNAL_NEW == compile ]] && chroot_build_packages

		if [[ $KERNEL_ONLY != yes ]]; then

			[[ $BSP_BUILD != yes ]] && debootstrap_ng

		else

			display_alert "Kernel build done" "@host" "info"
			display_alert "Target directory" "${DEB_STORAGE}/" "info"
			display_alert "File name" "${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb" "info"

		fi

	fi # end of else UBOOT_ONLY

	call_extension_method "run_after_build" << 'RUN_AFTER_BUILD'
*hook for function to run after build, i.e. to change owner of `$SRC`*
Really one of the last hooks ever called. The build has ended. Congratulations.
- *NOTE:* this will run only if there were no errors during build process.
RUN_AFTER_BUILD

	end=$(date +%s)
	runtime=$(((end - start) / 60))
	display_alert "Runtime" "$runtime min" "info"

	# Make it easy to repeat build by displaying build options used
	[ "$(systemd-detect-virt)" == 'docker' ] && BUILD_CONFIG='docker'
	display_alert "Repeat Build Options" "./compile.sh ${BUILD_CONFIG} BOARD=${BOARD} BRANCH=${BRANCH} \
$([[ -n $RELEASE ]] && echo "RELEASE=${RELEASE} ")\
$([[ -n $BUILD_MINIMAL ]] && echo "BUILD_MINIMAL=${BUILD_MINIMAL} ")\
$([[ -n $BUILD_DESKTOP ]] && echo "BUILD_DESKTOP=${BUILD_DESKTOP} ")\
$([[ -n $UBOOT_ONLY ]] && echo "UBOOT_ONLY=${UBOOT_ONLY} ")\
$([[ -n $KERNEL_ONLY ]] && echo "KERNEL_ONLY=${KERNEL_ONLY} ")\
$([[ -n $KERNEL_CONFIGURE ]] && echo "KERNEL_CONFIGURE=${KERNEL_CONFIGURE} ")\
$([[ -n $DESKTOP_ENVIRONMENT ]] && echo "DESKTOP_ENVIRONMENT=${DESKTOP_ENVIRONMENT} ")\
$([[ -n $DESKTOP_ENVIRONMENT_CONFIG_NAME ]] && echo "DESKTOP_ENVIRONMENT_CONFIG_NAME=${DESKTOP_ENVIRONMENT_CONFIG_NAME} ")\
$([[ -n $DESKTOP_APPGROUPS_SELECTED ]] && echo "DESKTOP_APPGROUPS_SELECTED=\"${DESKTOP_APPGROUPS_SELECTED}\" ")\
$([[ -n $DESKTOP_APT_FLAGS_SELECTED ]] && echo "DESKTOP_APT_FLAGS_SELECTED=\"${DESKTOP_APT_FLAGS_SELECTED}\" ")\
$([[ -n $COMPRESS_OUTPUTIMAGE ]] && echo "COMPRESS_OUTPUTIMAGE=${COMPRESS_OUTPUTIMAGE} ")\
" "ext"

}
