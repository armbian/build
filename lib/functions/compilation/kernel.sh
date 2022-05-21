function run_kernel_make() {
	set -e
	declare -a common_make_params_quoted common_make_envs full_command

	common_make_envs=(
		"CCACHE_BASEDIR=\"$(pwd)\""     # Base directory for ccache, for cache reuse # @TODO: experiment with this and the source path to maximize hit rate
		"PATH=\"${toolchain}:${PATH}\"" # Insert the toolchain first into the PATH.
		"DPKG_COLORS=always"            # Use colors for dpkg
		"XZ_OPT='--threads=0'"          # Use parallel XZ compression
		"TERM='${TERM}'"                # Pass the terminal type, so that 'make menuconfig' can work.
	)

	common_make_params_quoted=(
		# @TODO: introduce O=path/to/binaries, so sources and bins are not in the same dir.

		"$CTHREADS"                    # Parallel compile, "-j X" for X cpus
		"ARCH=${ARCHITECTURE}"         # Key param. Everything depends on this.
		"LOCALVERSION=-${LINUXFAMILY}" # Change the internal kernel version to include the family. Changing this causes recompiles # @TODO change to "localversion" file

		"CROSS_COMPILE=${CCACHE} ${KERNEL_COMPILER}"                           # added as prefix to every compiler invocation by make
		"KCFLAGS=-fdiagnostics-color=always -Wno-error=misleading-indentation" # Force GCC colored messages, downgrade misleading indentation to warning

		"SOURCE_DATE_EPOCH=${kernel_base_revision_ts}"        # https://reproducible-builds.org/docs/source-date-epoch/ and https://www.kernel.org/doc/html/latest/kbuild/reproducible-builds.html
		"KBUILD_BUILD_TIMESTAMP=${kernel_base_revision_date}" # https://www.kernel.org/doc/html/latest/kbuild/kbuild.html#kbuild-build-timestamp
		"KBUILD_BUILD_USER=armbian-build"                     # https://www.kernel.org/doc/html/latest/kbuild/kbuild.html#kbuild-build-user-kbuild-build-host
		"KBUILD_BUILD_HOST=armbian-bm"                        # https://www.kernel.org/doc/html/latest/kbuild/kbuild.html#kbuild-build-user-kbuild-build-host

		"KGZIP=pigz" "KBZIP2=pbzip2" # Parallel compression, use explicit parallel compressors https://lore.kernel.org/lkml/20200901151002.988547791@linuxfoundation.org/
	)

	# last statement, so it passes the result to calling function. "env -i" is used for empty env
	full_command=("${KERNEL_MAKE_RUNNER:-run_host_command_logged}" "env" "-i" "${common_make_envs[@]}"
		make "${common_make_params_quoted[@]@Q}" "$@" "${make_filter}")
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
	declare checked_out_revision_mtime="" checked_out_revision_ts="" # set by fetch_from_repo
	LOG_SECTION="kernel_prepare_git" do_with_logging do_with_hooks kernel_prepare_git

	# Capture date variables set by fetch_from_repo; it's the date of the last kernel revision
	declare kernel_base_revision_date
	declare kernel_base_revision_mtime="${checked_out_revision_mtime}"
	declare kernel_base_revision_ts="${checked_out_revision_ts}"
	kernel_base_revision_date="$(LC_ALL=C date -d "@${kernel_base_revision_ts}")"

	LOG_SECTION="kernel_maybe_clean" do_with_logging do_with_hooks kernel_maybe_clean
	local version hash pre_patch_version
	LOG_SECTION="kernel_prepare_patching" do_with_logging do_with_hooks kernel_prepare_patching
	LOG_SECTION="kernel_patching" do_with_logging do_with_hooks kernel_patching
	[[ $CREATE_PATCHES == yes ]] && userpatch_create "kernel" # create patch for manual source changes
	local version
	local toolchain

	# Check if we're gonna do some interactive configuration; if so, don't run kernel_config under logging manager.
	if [[ $KERNEL_CONFIGURE != yes ]]; then
		LOG_SECTION="kernel_config" do_with_logging do_with_hooks kernel_config
	else
		LOG_SECTION="kernel_config_interactive" do_with_hooks kernel_config
	fi

	LOG_SECTION="kernel_package_source" do_with_logging do_with_hooks kernel_package_source

	# @TODO: might be interesting to package kernel-headers at this stage.
	# @TODO: would allow us to have a "HEADERS_ONLY=yes" that can prepare arm64 headers on arm64 without building the whole kernel
	# @TODO: also it makes sense, logically, to package headers after configuration, since that's all what's needed; it's the same
	# @TODO: stage at which `dkms` would run (a configured, tool-built, kernel tree).

	# @TODO: might also be interesting to do the same for DTBs.
	# @TODO: those get packaged twice (once in linux-dtb and once in linux-image)
	# @TODO: but for the u-boot bootloader, only the linux-dtb is what matters.
	# @TODO: some users/maintainers do a lot of their work on "DTS/DTB only changes", which do require the kernel tree
	# @TODO: but the only testable artifacts are the .dtb themselves. Allow for a `DTB_ONLY=yes` might be useful.

	LOG_SECTION="kernel_build_and_package" do_with_logging do_with_hooks kernel_build_and_package

	display_alert "Done with" "kernel compile" "debug"
	cd "${kernel_work_dir}/.." || exit
	rm -f linux-firmware-image-*.deb # remove firmware image packages here - easier than patching ~40 packaging scripts at once
	run_host_command_logged rsync --remove-source-files -r ./*.deb "${DEB_STORAGE}/"
	return 0
}

function kernel_prepare_git() {
	if [[ -n $KERNELSOURCE ]]; then
		[[ -d "${kernel_work_dir}" ]] && cd "${kernel_work_dir}" && fasthash_debug "pre git, existing tree"

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
	if [[ $CLEAN_LEVEL == *make-kernel* ]]; then
		display_alert "Cleaning Kernel tree - CLEAN_LEVEL contains 'make-kernel'" "$LINUXSOURCEDIR" "info"
		(
			cd "${kernel_work_dir}"
			run_host_command_logged make ARCH="${ARCHITECTURE}" clean
		)
		fasthash_debug "post make clean"
	else
		display_alert "Not cleaning Kernel tree; use CLEAN_LEVEL=make-kernel if needed" "CLEAN_LEVEL=${CLEAN_LEVEL}" "debug"
	fi
}

function kernel_prepare_patching() {
	if [[ $USE_OVERLAYFS == yes ]]; then # @TODO: when is this set to yes?
		display_alert "Using overlayfs_wrapper" "kernel_${LINUXFAMILY}_${BRANCH}" "debug"
		kernel_work_dir=$(overlayfs_wrapper "wrap" "$SRC/cache/sources/$LINUXSOURCEDIR" "kernel_${LINUXFAMILY}_${BRANCH}")
	fi
	cd "${kernel_work_dir}" || exit

	# @TODO: why would we delete localversion?
	# @TODO: it should be the opposite, writing localversion to disk, _instead_ of passing it via make.
	# @TODO: if it turns out to be the case, do a commit with it... (possibly later, after patching?)
	rm -f localversion

	# read kernel version
	version=$(grab_version "$kernel_work_dir")
	pre_patch_version="${version}"
	display_alert "Pre-patch kernel version" "${pre_patch_version}" "debug"

	# read kernel git hash
	hash=$(git --git-dir="$kernel_work_dir"/.git rev-parse HEAD)
}

function kernel_patching() {
	## Start kernel patching process.
	## There's a few objectives here:
	## - (always) produce a fasthash: represents "what would be done" (eg: md5 of a patch, crc32 of description).
	## - (optionally) execute modification against living tree (eg: apply a patch, copy a file, etc). only if `DO_MODIFY=yes`
	## - (always) call mark_change_commit with the description of what was done and fasthash.
	declare -i patch_minimum_target_mtime="${kernel_base_revision_mtime}"
	display_alert "patch_minimum_target_mtime:" "${patch_minimum_target_mtime}" "debug"

	initialize_fasthash "kernel" "${hash}" "${pre_patch_version}" "${kernel_work_dir}"
	fasthash_debug "init"

	# Apply a series of patches if a series file exists
	local series_conf="${SRC}"/patch/kernel/${KERNELPATCHDIR}/series.conf
	if test -f "${series_conf}"; then
		display_alert "series.conf file visible. Apply"
		fasthash_branch "patches-${KERNELPATCHDIR}-series.conf"
		apply_patch_series "${kernel_work_dir}" "${series_conf}" # applies a series of patches, read from a file. calls process_patch_file
	fi

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
	else
		display_alert "Cross compilation" "target ${ARCH} on host $(dpkg --print-architecture)"
		toolchain=$(find_toolchain "$KERNEL_COMPILER" "$KERNEL_USE_GCC")
		[[ -z $toolchain ]] && exit_with_error "Could not find required toolchain" "${KERNEL_COMPILER}gcc $KERNEL_USE_GCC"
	fi

	kernel_compiler_version="$(eval env PATH="${toolchain}:${PATH}" "${KERNEL_COMPILER}gcc" -dumpversion)"
	display_alert "Compiler version" "${KERNEL_COMPILER}gcc ${kernel_compiler_version}" "info"

	# copy kernel config
	local COPY_CONFIG_BACK_TO=""

	if [[ $KERNEL_KEEP_CONFIG == yes && -f "${DEST}"/config/$LINUXCONFIG.config ]]; then
		display_alert "Using previous kernel config" "${DEST}/config/$LINUXCONFIG.config" "info"
		run_host_command_logged cp -pv "${DEST}/config/${LINUXCONFIG}.config" .config
	else
		if [[ -f $USERPATCHES_PATH/$LINUXCONFIG.config ]]; then
			display_alert "Using kernel config provided by user" "userpatches/$LINUXCONFIG.config" "info"
			run_host_command_logged cp -pv "${USERPATCHES_PATH}/${LINUXCONFIG}.config" .config
		elif [[ -f "${USERPATCHES_PATH}/config/kernel/${LINUXCONFIG}.config" ]]; then
			display_alert "Using kernel config provided by user in config/kernel folder" "config/kernel/${LINUXCONFIG}.config" "info"
			run_host_command_logged cp -pv "${USERPATCHES_PATH}/config/kernel/${LINUXCONFIG}.config" .config
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
		display_alert "Starting (interactive) kernel oldconfig" "${LINUXCONFIG}" "debug"

		run_kernel_make_dialog oldconfig

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
		[[ "${COPY_CONFIG_BACK_TO}" != "" ]] && run_host_command_logged cp -pv .config "${COPY_CONFIG_BACK_TO}"

		# export defconfig too if requested
		if [[ $KERNEL_EXPORT_DEFCONFIG == yes ]]; then
			run_kernel_make savedefconfig

			[[ -f defconfig ]] && run_host_command_logged cp -pv defconfig "${DEST}/config/${LINUXCONFIG}.defconfig"
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

function kernel_package_source() {
	[[ "${BUILD_KSRC}" != "yes" ]] && return 0

	display_alert "Creating kernel source package" "${LINUXCONFIG}" "info"

	local ts=${SECONDS}
	local sources_pkg_dir tmp_src_dir tarball_size package_size
	tmp_src_dir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.

	sources_pkg_dir="${tmp_src_dir}/${CHOSEN_KSRC}_${REVISION}_all"

	mkdir -p "${sources_pkg_dir}"/usr/src/ \
		"${sources_pkg_dir}/usr/share/doc/linux-source-${version}-${LINUXFAMILY}" \
		"${sources_pkg_dir}"/DEBIAN

	run_host_command_logged cp -v "${SRC}/config/kernel/${LINUXCONFIG}.config" "${sources_pkg_dir}/usr/src/${LINUXCONFIG}_${version}_${REVISION}_config"
	run_host_command_logged cp -v COPYING "${sources_pkg_dir}/usr/share/doc/linux-source-${version}-${LINUXFAMILY}/LICENSE"

	display_alert "Compressing sources for the linux-source package" "exporting from git" "info"
	cd "${kernel_work_dir}"

	local tar_prefix="${version}/"
	local output_tarball="${sources_pkg_dir}/usr/src/linux-source-${version}-${LINUXFAMILY}.tar.zst"

	# export tar with `git archive`; we point it at HEAD, but could be anything else too
	run_host_command_logged git archive "--prefix=${tar_prefix}" --format=tar HEAD "| zstdmt > '${output_tarball}'"
	tarball_size="$(du -h -s "${output_tarball}" | awk '{print $1}')"

	cat <<- EOF > "${sources_pkg_dir}"/DEBIAN/control
		Package: linux-source-${BRANCH}-${LINUXFAMILY}
		Version: ${version}-${BRANCH}-${LINUXFAMILY}+${REVISION}
		Architecture: all
		Maintainer: ${MAINTAINER} <${MAINTAINERMAIL}>
		Section: kernel
		Priority: optional
		Depends: binutils, coreutils
		Provides: linux-source, linux-source-${version}-${LINUXFAMILY}
		Recommends: gcc, make
		Description: This package provides the source code for the Linux kernel $version
	EOF

	fakeroot_dpkg_deb_build -Znone -z0 "${sources_pkg_dir}" "${sources_pkg_dir}.deb" # do not compress .deb, it already contains a zstd compressed tarball! ignores ${KDEB_COMPRESS} on purpose
	package_size="$(du -h -s "${sources_pkg_dir}.deb" | awk '{print $1}')"
	run_host_command_logged rsync --remove-source-files -r "${sources_pkg_dir}.deb" "${DEB_STORAGE}/"
	display_alert "$(basename "${sources_pkg_dir}.deb" ".deb") packaged" "$((SECONDS - ts)) seconds, ${tarball_size} tarball, ${package_size} .deb" "info"
}

function kernel_build_and_package() {
	local ts=${SECONDS}

	cd "${kernel_work_dir}"

	local -a build_targets=("all") # "All" builds the vmlinux/Image/Image.gz default for the ${ARCH}
	declare kernel_dest_install_dir
	kernel_dest_install_dir=$(mktemp -d "${WORKDIR}/kernel.temp.install.target.XXXXXXXXX") # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.

	# define dict with vars passed and target directories
	declare -A kernel_install_dirs=(
		["INSTALL_PATH"]="${kernel_dest_install_dir}/image/boot"  # Used by `make install`
		["INSTALL_MOD_PATH"]="${kernel_dest_install_dir}/modules" # Used by `make modules_install`
		#["INSTALL_HDR_PATH"]="${kernel_dest_install_dir}/libc_headers" # Used by `make headers_install` - disabled, only used for libc headers
	)

	build_targets+=(install modules_install) # headers_install disabled, only used for libc headers
	if [[ "${KERNEL_BUILD_DTBS:-yes}" == "yes" ]]; then
		display_alert "Kernel build will produce DTBs!" "DTBs YES" "debug"
		build_targets+=("dtbs_install")
		kernel_install_dirs+=(["INSTALL_DTBS_PATH"]="${kernel_dest_install_dir}/dtbs") # Used by `make dtbs_install`
	fi

	# loop over the keys above, get the value, create param value in array; also mkdir the dir
	declare -a install_make_params_quoted
	local dir_key
	for dir_key in "${!kernel_install_dirs[@]}"; do
		local dir="${kernel_install_dirs["${dir_key}"]}"
		local value="${dir_key}=${dir}"
		mkdir -p "${dir}"
		install_make_params_quoted+=("${value}")
	done

	display_alert "Building kernel" "${LINUXCONFIG} ${build_targets[*]}" "info"
	fasthash_debug "build"
	make_filter="| grep --line-buffered -v -e 'CC' -e 'LD' -e 'AR' -e 'INSTALL' -e 'SIGN' -e 'XZ' " \
		do_with_ccache_statistics \
		run_kernel_make_long_running "${install_make_params_quoted[@]@Q}" "${build_targets[@]}"
	fasthash_debug "build"

	cd "${kernel_work_dir}"
	prepare_kernel_packaging_debs "${kernel_work_dir}" "${kernel_dest_install_dir}" "${version}" kernel_install_dirs

	display_alert "Kernel built and packaged in" "$((SECONDS - ts)) seconds - ${version}-${LINUXFAMILY}" "info"
}

function do_with_ccache_statistics() {
	display_alert "Clearing ccache statistics" "ccache" "debug"
	ccache --zero-stats

	"$@"

	display_alert "Display ccache statistics" "ccache" "debug"
	run_host_command_logged ccache --show-stats
}
