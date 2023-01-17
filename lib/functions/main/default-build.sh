# This does NOT run under the logging manager. We should invoke the do_with_logging wrapper for
# strategic parts of this. Attention: rootfs does it's own logging, so just let that be.
function main_default_build_single() {
	# Check that WORKDIR_BASE_TMP exists; if not, create it.
	if [[ ! -d "${WORKDIR_BASE_TMP}" ]]; then
		mkdir -p "${WORKDIR_BASE_TMP}"
	fi

	# Check the sanity of WORKDIR_BASE_TMP regarding mount options.
	LOG_SECTION="check_dir_for_mount_options" do_with_logging check_dir_for_mount_options "${WORKDIR_BASE_TMP}" "main temporary dir"

	# Starting work. Export TMPDIR, which will be picked up by all `mktemp` invocations hopefully.
	# Runner functions in logging/runners.sh will explicitly unset TMPDIR before invoking chroot.
	# Invoking chroot directly will fail in subtle ways, so, please use the runner.sh functions.
	display_alert "Starting single build, exporting TMPDIR" "${WORKDIR}" "debug"
	LOG_SECTION="prepare_tmpfs_workdir" do_with_logging prepare_tmpfs_for "WORKDIR" "${WORKDIR}" # this adds its own cleanup handler, which deletes it if it was created
	add_cleanup_handler trap_handler_cleanup_workdir                                             # this is for when it is NOT a tmpfs, for any reason; it does not delete the dir itself.

	# 'declare -g -x': global, export
	declare -g -x TMPDIR="${WORKDIR}"                    # TMPDIR is default for a lot of stuff, but...
	declare -g -x CCACHE_TEMPDIR="${WORKDIR}/ccache_tmp" # Export CCACHE_TEMPDIR, under Workdir, which is hopefully under tmpfs. Thanks @the-Going for this.
	declare -g -x XDG_RUNTIME_DIR="${WORKDIR}/xdg_tmp"   # XDG_RUNTIME_DIR is used by the likes of systemd/freedesktop centric apps.

	declare start=$(date +%s)

	### Write config summary
	LOG_SECTION="config_summary" do_with_logging write_config_summary_output_file

	# Check and install dependencies, directory structure and settings
	prepare_host # this has its own logging sections, and is possibly interactive.

	# Aggregate packages, in its own logging section; this decides internally on KERNEL_ONLY=no
	LOG_SECTION="aggregate_packages" do_with_logging aggregate_packages

	# Create a directory inside WORKDIR with a "python" symlink to "/usr/bin/python2"; add it to PATH first.
	BIN_WORK_DIR="${WORKDIR}/bin"
	# No cleanup of this is necessary, since it's inside WORKDIR.
	mkdir -p "${BIN_WORK_DIR}"
	ln -s "/usr/bin/python2" "${BIN_WORK_DIR}/python"
	export PATH="${BIN_WORK_DIR}:${PATH}"

	if [[ "${JUST_INIT}" == "yes" ]]; then
		exit 0
	fi

	if [[ $CLEAN_LEVEL == *sources* ]]; then
		# early cleaning for sources, since fetch_and_build_host_tools() uses it.
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
	if [[ $IGNORE_UPDATES != yes ]]; then

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

	# skip image creation if exists. useful for CI when making a lot of images @TODO: hmm?
	if [ "$IMAGE_PRESENT" == yes ] && ls "${FINALDEST}/${VENDOR}_${REVISION}_${BOARD^}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}${DESKTOP_ENVIRONMENT:+_$DESKTOP_ENVIRONMENT}"*.xz 1> /dev/null 2>&1; then
		display_alert "Skipping image creation" "image already made - IMAGE_PRESENT is set" "wrn"
		exit
	fi

	# @TODO: dead code, remove
	## DEAD CODE IN ARMBIAN-NEXT ## # build additional packages
	## DEAD CODE IN ARMBIAN-NEXT ## if [[ $EXTERNAL_NEW == compile ]]; then
	## DEAD CODE IN ARMBIAN-NEXT ## 	display_alert "Building external packages" "$EXTERNAL - WARNING: this has not been armbian-nextifed yet and will fail." "warn"
	## DEAD CODE IN ARMBIAN-NEXT ## 	exit_with_error "buildpkg chroot_build_packages() nas not been ported to armbian-next yet, rpardini is a bum"
	## DEAD CODE IN ARMBIAN-NEXT ## 	LOG_SECTION="chroot_build_packages" do_with_logging chroot_build_packages
	## DEAD CODE IN ARMBIAN-NEXT ## fi

	# Reset owner of DEB_STORAGE, if needed. Might be a lot of packages there, but such is life.
	# @TODO: might be needed also during 'cleanup': if some package fails, the previous package might be left owned by root.
	reset_uid_owner "${DEB_STORAGE}"

	# end of kernel-only, so display what was built.
	if [[ $KERNEL_ONLY != yes ]]; then
		display_alert "Kernel build done" "@host" "target-reached"
		display_alert "Target directory" "${DEB_STORAGE}/" "info"
		display_alert "File name" "${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb" "info"
	fi

	# build rootfs, if not only kernel.
	if [[ $KERNEL_ONLY != yes ]]; then
		display_alert "Building image" "${BOARD}" "target-started"
		[[ $BSP_BUILD != yes ]] && build_rootfs_and_image # old debootstrap-ng. !!!LOGGING!!! handled inside, there are many sub-parts.
		display_alert "Done building image" "${BOARD}" "target-reached"
	fi

	call_extension_method "run_after_build" <<- 'RUN_AFTER_BUILD'
		*hook for function to run after build, i.e. to change owner of `$SRC`*
		Really one of the last hooks ever called. The build has ended. Congratulations.
		- *NOTE:* this will run only if there were no errors during build process.
	RUN_AFTER_BUILD

	end=$(date +%s)
	runtime=$(((end - start) / 60))
	# display_alert in its own logging section.
	LOG_SECTION="runtime_total" do_with_logging display_alert "Runtime" "$runtime min" "info"

	if armbian_is_running_in_container; then
		BUILD_CONFIG='docker' # @TODO: this is not true, depends on how we end up launching this.
	fi

	# Make it easy to repeat build by displaying build options used. Prepare array. @TODO this is inconsistent. Maybe something like the relaunch vars?
	local -a repeat_args=("./compile.sh" "${BUILD_CONFIG}" " BRANCH=${BRANCH}")
	[[ -n ${RELEASE} ]] && repeat_args+=("RELEASE=${RELEASE}")
	[[ -n ${BUILD_MINIMAL} ]] && repeat_args+=("BUILD_MINIMAL=${BUILD_MINIMAL}")
	[[ -n ${BUILD_DESKTOP} ]] && repeat_args+=("BUILD_DESKTOP=${BUILD_DESKTOP}")
	[[ -n ${KERNEL_ONLY} ]] && repeat_args+=("KERNEL_ONLY=${KERNEL_ONLY}")
	[[ -n ${KERNEL_CONFIGURE} ]] && repeat_args+=("KERNEL_CONFIGURE=${KERNEL_CONFIGURE}")
	[[ -n ${DESKTOP_ENVIRONMENT} ]] && repeat_args+=("DESKTOP_ENVIRONMENT=${DESKTOP_ENVIRONMENT}")
	[[ -n ${DESKTOP_ENVIRONMENT_CONFIG_NAME} ]] && repeat_args+=("DESKTOP_ENVIRONMENT_CONFIG_NAME=${DESKTOP_ENVIRONMENT_CONFIG_NAME}")
	[[ -n ${DESKTOP_APPGROUPS_SELECTED} ]] && repeat_args+=("DESKTOP_APPGROUPS_SELECTED=\"${DESKTOP_APPGROUPS_SELECTED}\"")
	[[ -n ${DESKTOP_APT_FLAGS_SELECTED} ]] && repeat_args+=("DESKTOP_APT_FLAGS_SELECTED=\"${DESKTOP_APT_FLAGS_SELECTED}\"")
	[[ -n ${COMPRESS_OUTPUTIMAGE} ]] && repeat_args+=("COMPRESS_OUTPUTIMAGE=${COMPRESS_OUTPUTIMAGE}")
	display_alert "Repeat Build Options" "${repeat_args[*]}" "ext" # * = expand array, space delimited, single-word.

}

function trap_handler_cleanup_workdir() {
	display_alert "Cleanup WORKDIR: $WORKDIR" "trap_handler_cleanup_workdir" "cleanup"
	unset TMPDIR
	if [[ -d "${WORKDIR}" ]]; then
		if [[ "${PRESERVE_WORKDIR}" != "yes" ]]; then
			display_alert "Cleaning up WORKDIR" "$(du -h -s "$WORKDIR")" "cleanup"
			# Remove all files and directories in WORKDIR, but not WORKDIR itself.
			rm -rf "${WORKDIR:?}"/* # Note this is protected by :?
		else
			display_alert "Preserving WORKDIR due to PRESERVE_WORKDIR=yes" "$(du -h -s "$WORKDIR")" "warn"
			# @TODO: tmpfs might just be unmounted, though.
		fi
	fi
}
