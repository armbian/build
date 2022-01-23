function run_kernel_make() {
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

	# last statement, so it passes the result to calling function.
	full_command=("${KERNEL_MAKE_RUNNER:-run_host_command_logged}" "${common_make_envs[@]}" make "$@" "${common_make_params_quoted[@]@Q}")
	display_alert "Kernel make" "${full_command[*]}" "debug"
	# echo "${full_command[@]}" >&2 # last-resort bash-quoting debugging
	"${full_command[@]}" # and exit with it's code, since it's the last statement
}

function run_kernel_make_dialog() {
	KERNEL_MAKE_RUNNER="run_host_command_dialog" run_kernel_make "$@"
}

function run_kernel_make_long_running() {
	KERNEL_MAKE_RUNNER="run_host_command_logged_long_running" run_kernel_make "$@"
}

compile_kernel() {
	if [[ $CLEAN_LEVEL == *make* ]]; then
		display_alert "Cleaning" "$LINUXSOURCEDIR" "info"
		(
			cd "${SRC}/cache/sources/${LINUXSOURCEDIR}"
			make ARCH="${ARCHITECTURE}" clean > /dev/null 2>&1
		)
	fi

	if [[ $USE_OVERLAYFS == yes ]]; then
		local kerneldir
		kerneldir=$(overlayfs_wrapper "wrap" "$SRC/cache/sources/$LINUXSOURCEDIR" "kernel_${LINUXFAMILY}_${BRANCH}")
	else
		local kerneldir="$SRC/cache/sources/$LINUXSOURCEDIR"
	fi
	cd "${kerneldir}" || exit

	rm -f localversion

	# read kernel version
	local version hash pre_patch_version
	version=$(grab_version "$kerneldir")
	pre_patch_version="${version}"
	display_alert "Pre-patch kernel version" "${pre_patch_version}" "debug"

	# read kernel git hash
	hash=$(improved_git --git-dir="$kerneldir"/.git rev-parse HEAD)

	# Apply a series of patches if a series file exists
	if test -f "${SRC}"/patch/kernel/"${KERNELPATCHDIR}"/series.conf; then
		display_alert "series.conf file visible. Apply"
		series_conf="${SRC}"/patch/kernel/${KERNELPATCHDIR}/series.conf

		# apply_patch_series <target dir> <full path to series file>
		apply_patch_series "${kerneldir}" "$series_conf"
	fi

	# build 3rd party drivers; # @TODO: does it build? or only patch?
	prepare_extra_kernel_drivers

	advanced_patch "kernel" "$KERNELPATCHDIR" "$BOARD" "" "$BRANCH" "$LINUXFAMILY-$BRANCH"

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
			run_kernel_make olddefconfig || {
				exit_with_error "Error kernel olddefconfig"
			}
		fi
	else
		display_alert "Starting kernel oldconfig+menuconfig" "${LINUXCONFIG}" "debug"

		run_kernel_make oldconfig

		# No logging for this. this is UI piece
		run_kernel_make_dialog "${KERNEL_MENUCONFIG:-menuconfig}" || {
			exit_with_error "Error kernel menuconfig failed"
		}

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
	run_kernel_make_long_running "${KERNEL_IMAGE_TYPE}" modules "${KERNEL_EXTRA_TARGETS:-dtbs}" || {
		exit_with_error "Failure during kernel compile" "@host"
	}

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
	run_kernel_make_long_running $kernel_packaging_target || {
		exit_with_error "Failure during kernel packaging" "@host"
	}

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

		# check if OLDHASHTARGET commit exists otherwise use oldest
		if [[ -z ${KERNEL_VERSION_LEVEL} ]]; then
			git -C ${kerneldir} cat-file -t ${OLDHASHTARGET} > /dev/null 2>&1 && OLDHASHTARGET=$(git -C ${kerneldir} show HEAD~199 --pretty=format:"%H" --no-patch)
		else
			git -C ${kerneldir} cat-file -t ${OLDHASHTARGET} > /dev/null 2>&1 && OLDHASHTARGET=$(git -C ${kerneldir} rev-list --max-parents=0 HEAD)
		fi

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
		echo "${hash_watch_1}${hash_watch_2}" | improved_git hash-object --stdin >> "${HASHTARGET}.githash"

		display_alert "Finished updating kernel hashes" "${LINUXCONFIG} $kernel_packaging_target" "info"
	fi
	return 0
}

create_linux-source_package() {
	ts=$(date +%s)
	local sources_pkg_dir tmp_src_dir
	tmp_src_dir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trap to clean-up.

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
