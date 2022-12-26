#!/usr/bin/env bash
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
	local version hash
	version=$(grab_version "$kerneldir")

	# read kernel git hash
	hash=$(improved_git --git-dir="$kerneldir"/.git rev-parse HEAD)

	# Apply a series of patches if a series file exists
	if test -f "${SRC}"/patch/kernel/${KERNELPATCHDIR}/series.conf; then
		display_alert "series.conf file visible. Apply"
		series_conf="${SRC}"/patch/kernel/${KERNELPATCHDIR}/series.conf

		# apply_patch_series <target dir> <full path to series file>
		apply_patch_series "${kerneldir}" "$series_conf"
	fi

	# build 3rd party drivers
	compilation_prepare

	advanced_patch "kernel" "$KERNELPATCHDIR" "$BOARD" "" "$BRANCH" "$LINUXFAMILY-$BRANCH"

	# create patch for manual source changes in debug mode
	[[ $CREATE_PATCHES == yes ]] && userpatch_create "kernel"

	# re-read kernel version after patching
	local version
	version=$(grab_version "$kerneldir")

	display_alert "Compiling $BRANCH kernel" "$version" "info"

	# compare with the architecture of the current Debian node
	# if it matches we use the system compiler
	if $(dpkg-architecture -e "${ARCH}"); then
		display_alert "Native compilation"
	elif [[ $(dpkg --print-architecture) == amd64 ]]; then
		local toolchain
		toolchain=$(find_toolchain "$KERNEL_COMPILER" "$KERNEL_USE_GCC")
		[[ -z $toolchain ]] && exit_with_error "Could not find required toolchain" "${KERNEL_COMPILER}gcc $KERNEL_USE_GCC"
	else
		exit_with_error "Architecture [$ARCH] is not supported"
	fi

	display_alert "Compiler version" "${KERNEL_COMPILER}gcc $(eval env PATH="${toolchain}:${PATH}" "${KERNEL_COMPILER}gcc" -dumpversion)" "info"

	# copy kernel config
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
		fi
	fi

	call_extension_method "custom_kernel_config" << 'CUSTOM_KERNEL_CONFIG'
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
	cp "${SRC}"/patch/misc/headers-debian-byteshift.patch /tmp

	if [[ $KERNEL_CONFIGURE != yes ]]; then
		if [[ $BRANCH == default ]]; then
			eval CCACHE_BASEDIR="$(pwd)" env PATH="${toolchain}:${PATH}" \
				'make ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" silentoldconfig'
		else
			# TODO: check if required
			eval CCACHE_BASEDIR="$(pwd)" env PATH="${toolchain}:${PATH}" \
				'make ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" olddefconfig'
		fi
	else
		eval CCACHE_BASEDIR="$(pwd)" env PATH="${toolchain}:${PATH}" \
			'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" oldconfig'
		eval CCACHE_BASEDIR="$(pwd)" env PATH="${toolchain}:${PATH}" \
			'make $CTHREADS ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" ${KERNEL_MENUCONFIG:-menuconfig}'

		[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Error kernel menuconfig failed"

		# store kernel config in easily reachable place
		display_alert "Exporting new kernel config" "$DEST/config/$LINUXCONFIG.config" "info"
		cp .config "${DEST}/config/${LINUXCONFIG}.config"
		# export defconfig too if requested
		if [[ $KERNEL_EXPORT_DEFCONFIG == yes ]]; then
			eval CCACHE_BASEDIR="$(pwd)" env PATH="${toolchain}:${PATH}" \
				'make ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" savedefconfig'
			[[ -f defconfig ]] && cp defconfig "${DEST}/config/${LINUXCONFIG}.defconfig"
		fi
	fi

	# create linux-source package - with already patched sources
	# We will build this package first and clear the memory.
	if [[ $BUILD_KSRC != no ]]; then
		create_linux-source_package
	fi

	echo -e "\n\t== kernel ==\n" >> "${DEST}"/${LOG_SUBPATH}/compilation.log
	eval CCACHE_BASEDIR="$(pwd)" env PATH="${toolchain}:${PATH}" \
		'make $CTHREADS ARCH=$ARCHITECTURE \
		CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" \
		$SRC_LOADADDR \
		LOCALVERSION="-$LINUXFAMILY" \
		$KERNEL_IMAGE_TYPE ${KERNEL_EXTRA_TARGETS:-modules dtbs} 2>>$DEST/${LOG_SUBPATH}/compilation.log' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" \
		--progressbox "Compiling kernel..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	if [[ ${PIPESTATUS[0]} -ne 0 || ! -f arch/$ARCHITECTURE/boot/$KERNEL_IMAGE_TYPE ]]; then
		grep -i error $DEST/${LOG_SUBPATH}/compilation.log
		exit_with_error "Kernel was not built" "@host"
	fi

	# different packaging for 4.3+
	if linux-version compare "${version}" ge 4.3; then
		local kernel_packing="bindeb-pkg"
	else
		local kernel_packing="deb-pkg"
	fi

	display_alert "Creating packages"

	# produce deb packages: image, headers, firmware, dtb
	echo -e "\n\t== deb packages: image, headers, firmware, dtb ==\n" >> "${DEST}"/${LOG_SUBPATH}/compilation.log
	eval CCACHE_BASEDIR="$(pwd)" env PATH="${toolchain}:${PATH}" \
		'make $CTHREADS $kernel_packing \
		KDEB_PKGVERSION=$REVISION \
		KDEB_COMPRESS=${DEB_COMPRESS} \
		BRANCH=$BRANCH \
		LOCALVERSION="-${LINUXFAMILY}" \
		KBUILD_DEBARCH=$ARCH \
		ARCH=$ARCHITECTURE \
		DEBFULLNAME="$MAINTAINER" \
		DEBEMAIL="$MAINTAINERMAIL" \
		CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" 2>>$DEST/${LOG_SUBPATH}/compilation.log' \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Creating kernel packages..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	cd .. || exit
	# remove firmare image packages here - easier than patching ~40 packaging scripts at once
	rm -f linux-firmware-image-*.deb

	rsync --remove-source-files -rq ./*.deb "${DEB_STORAGE}/${KERNEL_DISTRO_PATH}" || exit_with_error "Failed moving kernel DEBs"

	# store git hash to the file and create a change log
	HASHTARGET="${SRC}/cache/hash"$([[ ${BETA} == yes ]] && echo "-beta")"/linux-image-${BRANCH}-${LINUXFAMILY}"
	OLDHASHTARGET=$(head -1 "${HASHTARGET}.githash" 2> /dev/null)

	# check if OLDHASHTARGET commit exists otherwise use oldest
	if [[ -z ${KERNEL_VERSION_LEVEL} ]]; then
		git -C ${kerneldir} cat-file -t ${OLDHASHTARGET} > /dev/null 2>&1
		[[ $? -ne 0 ]] && OLDHASHTARGET=$(git -C ${kerneldir} show HEAD~199 --pretty=format:"%H" --no-patch)
	else
		git -C ${kerneldir} cat-file -t ${OLDHASHTARGET} > /dev/null 2>&1
		[[ $? -ne 0 ]] && OLDHASHTARGET=$(git -C ${kerneldir} rev-list --max-parents=0 HEAD)
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

	# hash origin
	echo "${hash}" > "${HASHTARGET}.githash"

	# hash_patches
	CALC_PATCHES=$(git -C $SRC log --format="%H" -1 -- $(realpath --relative-base="$SRC" "${SRC}/patch/kernel/${KERNELPATCHDIR}"))
	[[ -z "$CALC_PATCHES" ]] && CALC_PATCHES="null"
	echo "$CALC_PATCHES" >> "${HASHTARGET}.githash"

	# hash_kernel_config
	CALC_CONFIG=$(git -C $SRC log --format="%H" -1 -- $(realpath --relative-base="$SRC" "${SRC}/config/kernel/${LINUXCONFIG}.config"))
	[[ -z "$CALC_CONFIG" ]] && CALC_CONFIG="null"
	echo "$CALC_CONFIG" >> "${HASHTARGET}.githash"

}
