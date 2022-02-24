function run_kernel_make() {
	set -e
	declare -a common_make_params_quoted common_make_envs full_command

	common_make_envs=(
		"CCACHE_BASEDIR=\"$(pwd)\""     # Base directory for ccache, for cache reuse
		"PATH=\"${toolchain}:${PATH}\"" # Insert the toolchain first into the PATH.
		"DPKG_COLORS=always"            # Use colors for dpkg
	)

	common_make_params_quoted=(
		"$CTHREADS"                                         # Parallel compile, "-j X" for X cpus
		"LOCALVERSION=-${LINUXFAMILY}"                      # Kernel param
		"KDEB_PKGVERSION=${REVISION}"                       # deb package version
		"KDEB_COMPRESS=${DEB_COMPRESS}"                     # dpkg compression for deb
		"BRANCH=${BRANCH}"                                  # @TODO: rpardini: Wonder what BRANCH is used for during packaging?
		"INSTALL_HDR_PATH=debian/hdrtmp/usr"                # For packaging headers_install used for headers
		"INSTALL_MOD_PATH=debian/tmp"                       # For packaging modules for image package
		"INSTALL_DTBS_PATH=debian/dtbtmp/boot/dtbs_install" # For packaging DTBs for dtb package
		"ARCH=${ARCHITECTURE}"                              # Why?
		"KBUILD_DEBARCH=${ARCH}"                            # Where used?
		"DEBFULLNAME=${MAINTAINER}"                         # For changelog generation
		"DEBEMAIL=${MAINTAINERMAIL}"                        # idem
		"CROSS_COMPILE=${CCACHE} ${KERNEL_COMPILER}"        # Prefix for tool invocations.
	)

	common_make_params_quoted+=("KCFLAGS=-fdiagnostics-color=always") # Force GCC colored messages.

	# last statement, so it passes the result to calling function.
	full_command=("${KERNEL_MAKE_RUNNER:-run_host_command_logged}" "${common_make_envs[@]}"
		make "$@" "${common_make_params_quoted[@]@Q}" "${make_filter}")
	"${full_command[@]}" # and exit with it's code, since it's the last statement
}

function run_kernel_make_dialog() {
	KERNEL_MAKE_RUNNER="run_host_command_dialog" run_kernel_make "$@"
}

function run_kernel_make_long_running() {
	local seconds_start=${SECONDS} # Bash has a builtin SECONDS that is seconds since start of script
	KERNEL_MAKE_RUNNER="run_host_command_logged_long_running" run_kernel_make "$@"
	display_alert "Kernel Make '$*' took" "$((SECONDS - seconds_start)) seconds" "debug"
}

function compile_kernel() {
	local kernel_work_dir="${SRC}/cache/sources/${LINUXSOURCEDIR}"
	display_alert "Kernel build starting" "${LINUXSOURCEDIR}" "info"
	LOG_SECTION="kernel_prepare_git" do_with_logging do_with_hooks kernel_prepare_git
	LOG_SECTION="kernel_maybe_clean" do_with_logging do_with_hooks kernel_maybe_clean
	local version hash pre_patch_version
	local kernel_packaging_target
	LOG_SECTION="kernel_prepare_patching" do_with_logging do_with_hooks kernel_prepare_patching
	LOG_SECTION="kernel_patching" do_with_logging do_with_hooks kernel_patching
	[[ $CREATE_PATCHES == yes ]] && userpatch_create "kernel" # create patch for manual source changes
	local version
	local toolchain
	LOG_SECTION="kernel_config" do_with_logging do_with_hooks kernel_config
	LOG_SECTION="kernel_package_source" do_with_logging do_with_hooks kernel_package_source
	LOG_SECTION="kernel_make_headers_dtbs_image_modules" do_with_logging do_with_hooks kernel_make_headers_dtbs_image_modules
	LOG_SECTION="kernel_package" do_with_logging do_with_hooks kernel_package
	display_alert "Done with" "kernel compile" "debug"
	cd .. || exit
	rm -f linux-firmware-image-*.deb # remove firmware image packages here - easier than patching ~40 packaging scripts at once
	rsync --remove-source-files -rq ./*.deb "${DEB_STORAGE}/" || exit_with_error "Failed moving kernel DEBs"
	return 0
}

function kernel_prepare_git() {
	if [[ -n $KERNELSOURCE ]]; then
		display_alert "Downloading sources" "kernel" "git"

		# Does not work well with rpi for example: GIT_WARM_REMOTE_SHALLOW_AT_TAG="v${KERNEL_MAJOR_MINOR}" \
		# GIT_WARM_REMOTE_SHALLOW_AT_TAG sets GIT_WARM_REMOTE_SHALLOW_AT_DATE for you, as long as it is included by GIT_WARM_REMOTE_FETCH_TAGS
		# GIT_WARM_REMOTE_SHALLOW_AT_DATE is the only one really used for making shallow

		GIT_FIXED_WORKDIR="${LINUXSOURCEDIR}" \
			GIT_WARM_REMOTE_NAME="kernel-stable-${KERNEL_MAJOR_MINOR}" \
			GIT_WARM_REMOTE_URL="${MAINLINE_KERNEL_SOURCE}" \
			GIT_WARM_REMOTE_BRANCH="linux-${KERNEL_MAJOR_MINOR}.y" \
			GIT_WARM_REMOTE_FETCH_TAGS="v${KERNEL_MAJOR_MINOR}*" \
			GIT_WARM_REMOTE_SHALLOW_AT_TAG="${KERNEL_MAJOR_SHALLOW_TAG}" \
			GIT_WARM_REMOTE_BUNDLE="kernel-stable-${KERNEL_MAJOR_MINOR}" \
			GIT_COLD_BUNDLE_URL="${MAINLINE_KERNEL_COLD_BUNDLE_URL}" \
			fetch_from_repo "$KERNELSOURCE" "unused:set via GIT_FIXED_WORKDIR" "$KERNELBRANCH" "yes"
	fi
}

function kernel_maybe_clean() {
	if [[ $CLEAN_LEVEL == *make* ]]; then
		display_alert "Cleaning" "$LINUXSOURCEDIR" "info"
		(
			cd "${kernel_work_dir}"
			make ARCH="${ARCHITECTURE}" clean > /dev/null 2>&1
		)
		fasthash_debug "post make clean"
	fi
}

function kernel_prepare_patching() {

	if [[ $USE_OVERLAYFS == yes ]]; then
		display_alert "Using overlayfs_wrapper" "kernel_${LINUXFAMILY}_${BRANCH}" "debug"
		kernel_work_dir=$(overlayfs_wrapper "wrap" "$SRC/cache/sources/$LINUXSOURCEDIR" "kernel_${LINUXFAMILY}_${BRANCH}")
	fi
	cd "${kernel_work_dir}" || exit

	# @TODO: why would we delete localversion?
	rm -f localversion

	# read kernel version
	version=$(grab_version "$kernel_work_dir")
	pre_patch_version="${version}"
	display_alert "Pre-patch kernel version" "${pre_patch_version}" "debug"

	# different packaging for 4.3+
	kernel_packaging_target="deb-pkg"
	if linux-version compare "${version}" ge 4.3; then
		kernel_packaging_target="bindeb-pkg"
	fi

	# read kernel git hash
	hash=$(git --git-dir="$kernel_work_dir"/.git rev-parse HEAD)
}

function kernel_patching() {
	## Start kernel patching process.
	## There's a few objectives here:
	## - (always) produce a fasthash: represents "what would be done" (eg: md5 of a patch, crc32 of description).
	## - (optionally) execute modification against living tree (eg: apply a patch, copy a file, etc). only if `DO_MODIFY=yes`
	## - (always) call mark_change_commit with the description of what was done and fasthash.
	initialize_fasthash "kernel" "${hash}" "${pre_patch_version}" "${kernel_work_dir}"
	fasthash_debug "init"

	# Apply a series of patches if a series file exists
	local series_conf="${SRC}"/patch/kernel/${KERNELPATCHDIR}/series.conf
	if test -f "${series_conf}"; then
		display_alert "series.conf file visible. Apply"
		fasthash_branch "patches-${KERNELPATCHDIR}-series.conf"
		apply_patch_series "${kernel_work_dir}" "${series_conf}" # applies a series of patches, read from a file. calls process_patch_file
	fi

	# mostly local-based packaging fixes.
	fasthash_branch "packaging-patches"
	apply_kernel_patches_for_packaging "${kernel_work_dir}" "${version}" # calls process_patch_file and other stuff.

	# applies a humongous amount of patches coming from github repos.
	# it's mostly conditional, and very complex.
	# @TODO: re-enable after finishing converting it with fasthash magic
	# apply_kernel_patches_for_drivers  "${kernel_work_dir}" "${version}" # calls process_patch_file and other stuff. there is A LOT of it.

	# applies a series of patches, in directory order, from multiple directories (default/"user" patches)
	# @TODO: I believe using the $BOARD here is the most confusing thing in the whole of Armbian. It should be disabled.
	# @TODO: Armbian built kernels dont't vary per-board, but only per "$ARCH-$LINUXFAMILY-$BRANCH"
	# @TODO: allowing for board-specific kernel patches creates insanity. uboot is enough.
	fasthash_branch "patches-${KERNELPATCHDIR}-$BRANCH"
	advanced_patch "kernel" "$KERNELPATCHDIR" "$BOARD" "" "$BRANCH" "$LINUXFAMILY-$BRANCH" # calls process_patch_file, "target" is empty there

	fasthash_debug "finish"
	finish_fasthash "kernel" # this reports the final hash and creates git branch to build ID. All modifications commited.
}

function kernel_config() {
	# re-read kernel version after patching
	version=$(grab_version "$kernel_work_dir")

	display_alert "Compiling $BRANCH kernel" "$version" "info"

	# compare with the architecture of the current Debian node
	# if it matches we use the system compiler
	if dpkg-architecture -e "${ARCH}"; then
		display_alert "Native compilation" "target ${ARCH} on host $(dpkg --print-architecture)"
	elif [[ $(dpkg --print-architecture) == amd64 ]]; then
		display_alert "Cross compilation" "target ${ARCH} on host $(dpkg --print-architecture)"
		toolchain=$(find_toolchain "$KERNEL_COMPILER" "$KERNEL_USE_GCC")
		[[ -z $toolchain ]] && exit_with_error "Could not find required toolchain" "${KERNEL_COMPILER}gcc $KERNEL_USE_GCC"
	else
		display_alert "Unhandled cross compilation combo" "target ${ARCH} on host $(dpkg --print-architecture) - headers might not work" "warn"
	fi

	kernel_compiler_version="$(eval env PATH="${toolchain}:${PATH}" "${KERNEL_COMPILER}gcc" -dumpversion)"
	display_alert "Compiler version" "${KERNEL_COMPILER}gcc ${kernel_compiler_version}" "info"

	# copy kernel config
	local COPY_CONFIG_BACK_TO=""
	if [[ $KERNEL_KEEP_CONFIG == yes && -f "${DEST}"/config/$LINUXCONFIG.config ]]; then
		display_alert "Using previous kernel config" "${DEST}/config/$LINUXCONFIG.config" "info"
		cp -p "${DEST}/config/${LINUXCONFIG}.config" .config
	else
		if [[ -f $USERPATCHES_PATH/$LINUXCONFIG.config ]]; then
			display_alert "Using kernel config provided by user" "userpatches/$LINUXCONFIG.config" "info"
			cp -p "${USERPATCHES_PATH}/${LINUXCONFIG}.config" .config
		elif [[ -f "${USERPATCHES_PATH}/config/kernel/${LINUXCONFIG}.config" ]]; then
			display_alert "Using kernel config provided by user in config/kernel folder" "config/kernel/${LINUXCONFIG}.config" "info"
			cp -p "${USERPATCHES_PATH}/config/kernel/${LINUXCONFIG}.config" .config
		else
			display_alert "Using kernel config file" "config/kernel/$LINUXCONFIG.config" "info"
			cp -p "${SRC}/config/kernel/${LINUXCONFIG}.config" .config
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

	# hack for deb builder. To pack what's missing in headers pack.
	cp "${SRC}"/patch/misc/headers-debian-byteshift.patch /tmp # @TODO: ok, but why /tmp? It's leaking there.

	display_alert "Kernel configuration" "${LINUXCONFIG}" "info"

	if [[ $KERNEL_CONFIGURE != yes ]]; then
		run_kernel_make olddefconfig # @TODO: what is this? does it fuck up dates?
	else
		display_alert "Starting kernel oldconfig+menuconfig" "${LINUXCONFIG}" "debug"

		run_kernel_make oldconfig

		# No logging for this. this is UI piece
		run_kernel_make_dialog "${KERNEL_MENUCONFIG:-menuconfig}"

		# Capture new date. Otherwise changes not detected by make.
		kernel_config_mtime=$(get_file_modification_time ".config")

		# store kernel config in easily reachable place
		display_alert "Exporting new kernel config" "$DEST/config/$LINUXCONFIG.config" "info"
		cp .config "${DEST}/config/${LINUXCONFIG}.config"

		# store back into original LINUXCONFIG too, if it came from there, so it's pending commits when done.
		[[ "${COPY_CONFIG_BACK_TO}" != "" ]] && cp -v .config "${COPY_CONFIG_BACK_TO}"

		# export defconfig too if requested
		if [[ $KERNEL_EXPORT_DEFCONFIG == yes ]]; then
			run_kernel_make savedefconfig

			[[ -f defconfig ]] && cp defconfig "${DEST}/config/${LINUXCONFIG}.defconfig"
		fi
	fi

	# Restore the date of .config. Above delta is a pure function, theoretically.
	set_files_modification_time "${kernel_config_mtime}" ".config"
}

function kernel_package_source() {
	# create linux-source package - with already patched sources
	# We will build this package first and clear the memory.
	if [[ $BUILD_KSRC != no ]]; then
		display_alert "Creating kernel source package" "${LINUXCONFIG}" "info"
		create_linux-source_package
	fi
}

create_linux-source_package() {
	ts=$(date +%s)
	local sources_pkg_dir tmp_src_dir
	tmp_src_dir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.

	sources_pkg_dir=${tmp_src_dir}/${CHOSEN_KSRC}_${REVISION}_all
	mkdir -p "${sources_pkg_dir}"/usr/src/ \
		"${sources_pkg_dir}"/usr/share/doc/linux-source-${version}-${LINUXFAMILY} \
		"${sources_pkg_dir}"/DEBIAN

	cp "${SRC}/config/kernel/${LINUXCONFIG}.config" "default_${LINUXCONFIG}.config"
	xz < .config > "${sources_pkg_dir}/usr/src/${LINUXCONFIG}_${version}_${REVISION}_config.xz"

	display_alert "Compressing sources for the linux-source package"
	tar cp --directory="$kernel_work_dir" --exclude='.git' --owner=root . |
		pv -N "$(logging_echo_prefix_for_pv "compress_kernel_sources") $display_name" -p -b -r -s "$(du -sb "$kernel_work_dir" --exclude=='.git' | cut -f1)" |
		pixz -0 > "${sources_pkg_dir}/usr/src/linux-source-${version}-${LINUXFAMILY}.tar.xz" # @TODO: .deb will compress this later. -0 for now, but should be a plain tar
	cp COPYING "${sources_pkg_dir}/usr/share/doc/linux-source-${version}-${LINUXFAMILY}/LICENSE"

	cat <<- EOF > "${sources_pkg_dir}"/DEBIAN/control
		Package: linux-source-${version}-${BRANCH}-${LINUXFAMILY}
		Version: ${version}-${BRANCH}-${LINUXFAMILY}+${REVISION}
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Section: kernel
		Priority: optional
		Depends: binutils, coreutils
		Provides: linux-source, linux-source-${version}-${LINUXFAMILY}
		Recommends: gcc, make
		Description: This package provides the source code for the Linux kernel $version
	EOF

	fakeroot_dpkg_deb_build -z0 "${sources_pkg_dir}" "${sources_pkg_dir}.deb"
	rsync --remove-source-files -rq "${sources_pkg_dir}.deb" "${DEB_STORAGE}/"

	te=$(date +%s)
	display_alert "Make the linux-source package" "$(($te - $ts)) sec." "info"
}

function kernel_make_headers_dtbs_image_modules() {
	local -a build_targets=("headers")
	[[ "${KERNEL_BUILD_DTBS:-yes}" == "yes" ]] && build_targets+=("dtbs")
	build_targets+=("${KERNEL_IMAGE_TYPE}" modules)

	display_alert "Compiling Kernel" "${LINUXCONFIG} ${KERNEL_IMAGE_TYPE}" "info"
	fasthash_debug "pre-compile"
	make_filter="| grep --line-buffered -v -e 'CC' -e 'LD' -e 'AR'" run_kernel_make_long_running "${build_targets[@]}"
	fasthash_debug "post-compile"

	if [[ "${DOUBLE_COMPILE_KERNEL}" == "yes" ]]; then
		display_alert "DOUBLE Compiling Kernel" "${LINUXCONFIG} ${KERNEL_IMAGE_TYPE}" "info"
		fasthash_debug "pre-double-compile"
		run_kernel_make_long_running "${build_targets[@]}"
		fasthash_debug "post-double-compile"
	fi

	# Check for built kernel image file file; can override default with KERNEL_IMAGE_TYPE_PATH
	local check_built_kernel_file="${kernel_work_dir}/${KERNEL_IMAGE_TYPE_PATH:-"arch/${ARCHITECTURE}/boot/${KERNEL_IMAGE_TYPE}"}"
	if [[ ! -f "${check_built_kernel_file}" ]]; then
		exit_with_error "Kernel was not built" "${check_built_kernel_file}"
	fi
}

function kernel_package() {

	local -a prepackage_targets=(modules_install headers_install)
	[[ "${KERNEL_BUILD_DTBS:-yes}" == "yes" ]] && prepackage_targets+=("dtbs_install")

	display_alert "Packaging Kernel" "${LINUXCONFIG} $kernel_packaging_target" "info"

	# Prepare for packaging, using the exact same options as original compile.
	display_alert "Installing kernel headers and modules for packaging" "${LINUXCONFIG} ${prepackage_targets[*]}" "info"
	fasthash_debug "pre-prepackage"
	make_filter="| grep --line-buffered -v -e 'INSTALL' -e 'SIGN' -e 'XZ'" run_kernel_make_long_running "${prepackage_targets[@]}"
	fasthash_debug "post-prepackage"

	# produce deb packages: image, headers, firmware, dtb
	# This mostly only does
	fasthash_debug "pre-packaging"
	run_kernel_make_long_running $kernel_packaging_target
	fasthash_debug "post-packaging"

	if [[ "${DOUBLE_COMPILE_KERNEL}" == "yes" ]]; then
		display_alert "DOUBLE Packaging Kernel, Headers and DTBs" "${LINUXCONFIG} $kernel_packaging_target" "info"
		fasthash_debug "pre-double-packaging"
		run_kernel_make_long_running $kernel_packaging_target
		fasthash_debug "post-double-packaging"
	fi

	display_alert "Package building done" "${LINUXCONFIG} $kernel_packaging_target" "info"
}
