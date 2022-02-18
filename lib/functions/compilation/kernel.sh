function run_kernel_make() {
	set -e
	declare -a common_make_params_quoted common_make_envs full_command

	common_make_envs=(
		"CCACHE_BASEDIR=\"$(pwd)\""     # Base directory for ccache, for cache reuse
		"PATH=\"${toolchain}:${PATH}\"" # Insert the toolchain first into the PATH.
	)

	common_make_params_quoted=(
		"$CTHREADS"                                  # Parallel compile, "-j X" for X cpus
		"LOCALVERSION=-${LINUXFAMILY}"               # Kernel param
		"KDEB_PKGVERSION=${REVISION}"                # deb package version
		"KDEB_COMPRESS=${DEB_COMPRESS}"              # dpkg compression for deb
		"BRANCH=${BRANCH}"                           # @TODO: rpardini: Wonder what BRANCH is used for during packaging?
		"ARCH=${ARCHITECTURE}"                       # Why?
		"KBUILD_DEBARCH=${ARCH}"                     # Where used?
		"DEBFULLNAME=${MAINTAINER}"                  # For changelog generation
		"DEBEMAIL=${MAINTAINERMAIL}"                 # idem
		"CROSS_COMPILE=${CCACHE} ${KERNEL_COMPILER}" # Prefix for tool invocations.
	)

	common_make_params_quoted+=("KCFLAGS=-fdiagnostics-color=always") # Force GCC colored messages.

	# last statement, so it passes the result to calling function.
	full_command=("${KERNEL_MAKE_RUNNER:-run_host_command_logged}" "${common_make_envs[@]}" make "$@" "${common_make_params_quoted[@]@Q}")
	"${full_command[@]}" # and exit with it's code, since it's the last statement
}

function run_kernel_make_dialog() {
	KERNEL_MAKE_RUNNER="run_host_command_dialog" run_kernel_make "$@"
}

function run_kernel_make_long_running() {
	KERNEL_MAKE_RUNNER="run_host_command_logged_long_running" run_kernel_make "$@"
}

function compile_kernel() {
	if [[ $CLEAN_LEVEL == *make* ]]; then
		display_alert "Cleaning" "$LINUXSOURCEDIR" "info"
		(
			cd "${SRC}/cache/sources/${LINUXSOURCEDIR}"
			make ARCH="${ARCHITECTURE}" clean > /dev/null 2>&1
		)
	fi

	local kerneldir="$SRC/cache/sources/$LINUXSOURCEDIR"
	if [[ $USE_OVERLAYFS == yes ]]; then
		display_alert "Using overlayfs_wrapper" "kernel_${LINUXFAMILY}_${BRANCH}" "debug"
		kerneldir=$(overlayfs_wrapper "wrap" "$SRC/cache/sources/$LINUXSOURCEDIR" "kernel_${LINUXFAMILY}_${BRANCH}")
	fi
	cd "${kerneldir}" || exit

	rm -f localversion

	# read kernel version
	local version hash pre_patch_version
	version=$(grab_version "$kerneldir")
	pre_patch_version="${version}"
	display_alert "Pre-patch kernel version" "${pre_patch_version}" "debug"

	# read kernel git hash
	hash=$(git --git-dir="$kerneldir"/.git rev-parse HEAD)

	## Start kernel patching process.
	## There's a few objectives here:
	## - (always) produce a fasthash: represents "what would be done" (eg: md5 of a patch, crc32 of description).
	## - (optionally) execute modification against living tree (eg: apply a patch, copy a file, etc). only if `DO_MODIFY=yes`
	## - (always) call mark_change_commit with the description of what was done and fasthash.
	initialize_fasthash "kernel" "${hash}" "${pre_patch_version}" "${kerneldir}"
	declare -a fast_hash_list=()

	# Apply a series of patches if a series file exists
	local series_conf="${SRC}"/patch/kernel/${KERNELPATCHDIR}/series.conf
	if test -f "${series_conf}"; then
		display_alert "series.conf file visible. Apply"
		fasthash_branch "patches-${KERNELPATCHDIR}-series.conf"
		apply_patch_series "${kerneldir}" "${series_conf}" # applies a series of patches, read from a file. calls process_patch_file
	fi

	# mostly local-based packaging fixes.
	fasthash_branch "packaging-patches"
	apply_kernel_patches_for_packaging "${kerneldir}" "${version}" # calls process_patch_file and other stuff.

	# applies a humongous amount of patches coming from github repos.
	# it's mostly conditional, and very complex.
	# @TODO: re-enable after finishing converting it with fasthash magic
	# apply_kernel_patches_for_drivers  "${kerneldir}" "${version}" # calls process_patch_file and other stuff. there is A LOT of it.

	# applies a series of patches, in directory order, from multiple directories (default/"user" patches)
	# @TODO: I believe using the $BOARD here is the most confusing thing in the whole of Armbian. It should be disabled.
	# @TODO: Armbian built kernels dont't vary per-board, but only per "$ARCH-$LINUXFAMILY-$BRANCH"
	# @TODO: allowing for board-specific kernel patches creates insanity. uboot is enough.
	fasthash_branch "patches-${KERNELPATCHDIR}-$BRANCH"
	advanced_patch "kernel" "$KERNELPATCHDIR" "$BOARD" "" "$BRANCH" "$LINUXFAMILY-$BRANCH" # calls process_patch_file, "target" is empty there

	finish_fasthash "kernel" # this reports the final hash and creates git branch to build ID. All modifications commited.

	# create patch for manual source changes in debug mode
	[[ $CREATE_PATCHES == yes ]] && userpatch_create "kernel"

	# re-read kernel version after patching
	local version
	version=$(grab_version "$kerneldir")

	display_alert "Compiling $BRANCH kernel" "$version" "info"

	# compare with the architecture of the current Debian node
	# if it matches we use the system compiler
	if dpkg-architecture -e "${ARCH}"; then
		display_alert "Native compilation" "target ${ARCH} on host $(dpkg --print-architecture)"
	elif [[ $(dpkg --print-architecture) == amd64 ]]; then
		display_alert "Cross compilation" "target ${ARCH} on host $(dpkg --print-architecture)"
		local toolchain
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
		else
			display_alert "Using kernel config file" "config/kernel/$LINUXCONFIG.config" "info"
			cp -p "${SRC}/config/kernel/${LINUXCONFIG}.config" .config
			COPY_CONFIG_BACK_TO="${SRC}/config/kernel/${LINUXCONFIG}.config"
		fi
	fi

	call_extension_method "custom_kernel_config" <<- 'CUSTOM_KERNEL_CONFIG'
		*Kernel .config is in place, still clean from git version*
		Called after ${LINUXCONFIG}.config is put in place (.config).
		Before any olddefconfig any Kconfig make is called.
		A good place to customize the .config directly.
	CUSTOM_KERNEL_CONFIG

	# hack for OdroidXU4. Copy firmare files
	if [[ $BOARD == odroidxu4 ]]; then
		mkdir -p "${kerneldir}/firmware/edid"
		cp "${SRC}"/packages/blobs/odroidxu4/*.bin "${kerneldir}/firmware/edid"
	fi

	# hack for deb builder. To pack what's missing in headers pack.
	cp "${SRC}"/patch/misc/headers-debian-byteshift.patch /tmp # @TODO: ok, but why /tmp? It's leaking there.

	display_alert "Kernel configuration" "${LINUXCONFIG}" "info"

	if [[ $KERNEL_CONFIGURE != yes ]]; then
		if [[ $BRANCH == default ]]; then
			run_kernel_make silentoldconfig # This will exit with generic error if it fails.
		else
			# TODO: check if required
			run_kernel_make olddefconfig
		fi
	else
		display_alert "Starting kernel oldconfig+menuconfig" "${LINUXCONFIG}" "debug"

		run_kernel_make oldconfig

		# No logging for this. this is UI piece
		run_kernel_make_dialog "${KERNEL_MENUCONFIG:-menuconfig}"

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

	# create linux-source package - with already patched sources
	# We will build this package first and clear the memory.
	if [[ $BUILD_KSRC != no ]]; then
		display_alert "Creating kernel source package" "${LINUXCONFIG}" "info"
		create_linux-source_package
	fi

	display_alert "Compiling Kernel" "${LINUXCONFIG} ${KERNEL_IMAGE_TYPE}" "info"
	run_kernel_make_long_running "${KERNEL_IMAGE_TYPE}" modules "${KERNEL_EXTRA_TARGETS:-dtbs}"
	#run_kernel_make "${KERNEL_IMAGE_TYPE}" modules "${KERNEL_EXTRA_TARGETS:-dtbs}"

	if [[ ! -f arch/$ARCHITECTURE/boot/$KERNEL_IMAGE_TYPE ]]; then
		exit_with_error "Kernel was not built" "arch/$ARCHITECTURE/boot/$KERNEL_IMAGE_TYPE"
	fi

	# different packaging for 4.3+
	if linux-version compare "${version}" ge 4.3; then
		local kernel_packaging_target="bindeb-pkg"
	else
		local kernel_packaging_target="deb-pkg"
	fi

	display_alert "Creating kernel packages" "${LINUXCONFIG} $kernel_packaging_target" "info"

	# produce deb packages: image, headers, firmware, dtb
	run_kernel_make_long_running $kernel_packaging_target

	display_alert "Package building done" "${LINUXCONFIG} $kernel_packaging_target" "info"

	cd .. || exit
	# remove firmware image packages here - easier than patching ~40 packaging scripts at once
	rm -f linux-firmware-image-*.deb

	rsync --remove-source-files -rq ./*.deb "${DEB_STORAGE}/" || exit_with_error "Failed moving kernel DEBs"

	if [[ "a" == "b" ]]; then # @TODO DISABLED! TOO CRAZY
		display_alert "Update Kernel hashes" "${LINUXCONFIG} $kernel_packaging_target"

		# store git hash to the file and create a change log
		HASHTARGET="${SRC}/cache/hash$([[ ${BETA} == yes ]] && echo "-beta" || true)/linux-image-${BRANCH}-${LINUXFAMILY}"
		OLDHASHTARGET=$(head -1 "${HASHTARGET}.githash" 2> /dev/null || true)

		git -C ${kerneldir} cat-file -t ${OLDHASHTARGET} > /dev/null 2>&1 && OLDHASHTARGET=$(git -C ${kerneldir} rev-list --max-parents=0 HEAD)

		[[ -z ${KERNELPATCHDIR} ]] && KERNELPATCHDIR=$LINUXFAMILY-$BRANCH
		[[ -z ${LINUXCONFIG} ]] && LINUXCONFIG=linux-$LINUXFAMILY-$BRANCH

		# calculate URL
		if [[ "$KERNELSOURCE" == *"github.com"* ]]; then
			URL="${KERNELSOURCE/git:/https:}/commit/${HASH}"
		elif [[ "$KERNELSOURCE" == *"kernel.org"* ]]; then
			URL="${KERNELSOURCE/git:/https:}/commit/?h=$(echo $KERNELBRANCH | cut -d":" -f2)&id=${HASH}"
		else
			URL="${KERNELSOURCE}/+/$HASH"
		fi

		# create change log
		git --no-pager -C ${kerneldir} log --abbrev-commit --oneline --no-patch --no-merges --date-order --date=format:'%Y-%m-%d %H:%M:%S' --pretty=format:'%C(black bold)%ad%Creset%C(auto) | %s | <%an> | <a href='$URL'%H>%H</a>' ${OLDHASHTARGET}..${hash} > "${HASHTARGET}.gitlog"

		echo "${hash}" > "${HASHTARGET}.githash"
		hash_watch_1=$(LC_COLLATE=C find -L "${SRC}/patch/kernel/${KERNELPATCHDIR}"/ -name '*.patch' -mindepth 1 -maxdepth 1 -printf '%s %P\n' 2> /dev/null | LC_COLLATE=C sort -n)
		hash_watch_2=$(cat "${SRC}/config/kernel/${LINUXCONFIG}.config")
		echo "${hash_watch_1}${hash_watch_2}" | git hash-object --stdin >> "${HASHTARGET}.githash"

		display_alert "Finished updating kernel hashes" "${LINUXCONFIG} $kernel_packaging_target" "info"
	fi
	return 0
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
	tar cp --directory="$kerneldir" --exclude='.git' --owner=root . |
		pv -N "$(logging_echo_prefix_for_pv "compress_kernel_sources") $display_name" -p -b -r -s "$(du -sb "$kerneldir" --exclude=='.git' | cut -f1)" |
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
