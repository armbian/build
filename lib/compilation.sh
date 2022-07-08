#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:

# compile_atf
# compile_uboot
# compile_kernel
# compile_firmware
# compile_armbian-config
# compile_xilinx_bootgen
# grab_version
# find_toolchain
# advanced_patch
# process_patch_file
# userpatch_create
# overlayfs_wrapper




compile_atf()
{
	if [[ $CLEAN_LEVEL == *make* ]]; then
		display_alert "Cleaning" "$ATFSOURCEDIR" "info"
		(cd "${SRC}/cache/sources/${ATFSOURCEDIR}"; make distclean > /dev/null 2>&1)
	fi

	if [[ $USE_OVERLAYFS == yes ]]; then
		local atfdir
		atfdir=$(overlayfs_wrapper "wrap" "$SRC/cache/sources/$ATFSOURCEDIR" "atf_${LINUXFAMILY}_${BRANCH}")
	else
		local atfdir="$SRC/cache/sources/$ATFSOURCEDIR"
	fi
	cd "$atfdir" || exit

	display_alert "Compiling ATF" "" "info"

# build aarch64
  if [[ $(dpkg --print-architecture) == amd64 ]]; then

	local toolchain
	toolchain=$(find_toolchain "$ATF_COMPILER" "$ATF_USE_GCC")
	[[ -z $toolchain ]] && exit_with_error "Could not find required toolchain" "${ATF_COMPILER}gcc $ATF_USE_GCC"

	if [[ -n $ATF_TOOLCHAIN2 ]]; then
		local toolchain2_type toolchain2_ver toolchain2
		toolchain2_type=$(cut -d':' -f1 <<< "${ATF_TOOLCHAIN2}")
		toolchain2_ver=$(cut -d':' -f2 <<< "${ATF_TOOLCHAIN2}")
		toolchain2=$(find_toolchain "$toolchain2_type" "$toolchain2_ver")
		[[ -z $toolchain2 ]] && exit_with_error "Could not find required toolchain" "${toolchain2_type}gcc $toolchain2_ver"
	fi

# build aarch64
  fi

	display_alert "Compiler version" "${ATF_COMPILER}gcc $(eval env PATH="${toolchain}:${PATH}" "${ATF_COMPILER}gcc" -dumpversion)" "info"

	local target_make target_patchdir target_files
	target_make=$(cut -d';' -f1 <<< "${ATF_TARGET_MAP}")
	target_patchdir=$(cut -d';' -f2 <<< "${ATF_TARGET_MAP}")
	target_files=$(cut -d';' -f3 <<< "${ATF_TARGET_MAP}")

	advanced_patch "atf" "${ATFPATCHDIR}" "$BOARD" "$target_patchdir" "$BRANCH" "${LINUXFAMILY}-${BOARD}-${BRANCH}"

	# create patch for manual source changes
	[[ $CREATE_PATCHES == yes ]] && userpatch_create "atf"

	echo -e "\n\t==  atf  ==\n" >> "${DEST}"/${LOG_SUBPATH}/compilation.log
	# ENABLE_BACKTRACE="0" has been added to workaround a regression in ATF.
	# Check: https://github.com/armbian/build/issues/1157
	eval CCACHE_BASEDIR="$(pwd)" env PATH="${toolchain}:${toolchain2}:${PATH}" \
		'make ENABLE_BACKTRACE="0" $target_make $CTHREADS \
		CROSS_COMPILE="$CCACHE $ATF_COMPILER"' 2>> "${DEST}"/${LOG_SUBPATH}/compilation.log \
		${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/compilation.log'} \
		${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling ATF..." $TTY_Y $TTY_X'} \
		${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

	[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "ATF compilation failed"

	[[ $(type -t atf_custom_postprocess) == function ]] && atf_custom_postprocess

	atftempdir=$(mktemp -d)
	chmod 700 ${atftempdir}
	trap "ret=\$?; rm -rf \"${atftempdir}\" ; exit \$ret" 0 1 2 3 15

	# copy files to temp directory
	for f in $target_files; do
		local f_src
		f_src=$(cut -d':' -f1 <<< "${f}")
		if [[ $f == *:* ]]; then
			local f_dst
			f_dst=$(cut -d':' -f2 <<< "${f}")
		else
			local f_dst
			f_dst=$(basename "${f_src}")
		fi
		[[ ! -f $f_src ]] && exit_with_error "ATF file not found" "$(basename "${f_src}")"
		cp "${f_src}" "${atftempdir}/${f_dst}"
	done

	# copy license file to pack it to u-boot package later
	[[ -f license.md ]] && cp license.md "${atftempdir}"/
}




compile_uboot()
{
	# not optimal, but extra cleaning before overlayfs_wrapper should keep sources directory clean
	if [[ $CLEAN_LEVEL == *make* ]]; then
		display_alert "Cleaning" "$BOOTSOURCEDIR" "info"
		(cd "${SRC}/cache/sources/${BOOTSOURCEDIR}"; make clean > /dev/null 2>&1)
	fi

	if [[ $USE_OVERLAYFS == yes ]]; then
		local ubootdir
		ubootdir=$(overlayfs_wrapper "wrap" "$SRC/cache/sources/$BOOTSOURCEDIR" "u-boot_${LINUXFAMILY}_${BRANCH}")
	else
		local ubootdir="$SRC/cache/sources/$BOOTSOURCEDIR"
	fi
	cd "${ubootdir}" || exit

	# read uboot version
	local version hash
	version=$(grab_version "$ubootdir")
	hash=$(improved_git --git-dir="$ubootdir"/.git rev-parse HEAD)

	display_alert "Compiling u-boot" "$version" "info"

# build aarch64
  if [[ $(dpkg --print-architecture) == amd64 ]]; then

	local toolchain
	toolchain=$(find_toolchain "$UBOOT_COMPILER" "$UBOOT_USE_GCC")
	[[ -z $toolchain ]] && exit_with_error "Could not find required toolchain" "${UBOOT_COMPILER}gcc $UBOOT_USE_GCC"

	if [[ -n $UBOOT_TOOLCHAIN2 ]]; then
		local toolchain2_type toolchain2_ver toolchain2
		toolchain2_type=$(cut -d':' -f1 <<< "${UBOOT_TOOLCHAIN2}")
		toolchain2_ver=$(cut -d':' -f2 <<< "${UBOOT_TOOLCHAIN2}")
		toolchain2=$(find_toolchain "$toolchain2_type" "$toolchain2_ver")
		[[ -z $toolchain2 ]] && exit_with_error "Could not find required toolchain" "${toolchain2_type}gcc $toolchain2_ver"
	fi

# build aarch64
  fi

	display_alert "Compiler version" "${UBOOT_COMPILER}gcc $(eval env PATH="${toolchain}:${toolchain2}:${PATH}" "${UBOOT_COMPILER}gcc" -dumpversion)" "info"
	[[ -n $toolchain2 ]] && display_alert "Additional compiler version" "${toolchain2_type}gcc $(eval env PATH="${toolchain}:${toolchain2}:${PATH}" "${toolchain2_type}gcc" -dumpversion)" "info"

	# create directory structure for the .deb package
	uboottempdir=$(mktemp -d)
	chmod 700 ${uboottempdir}
	trap "ret=\$?; rm -rf \"${uboottempdir}\" ; exit \$ret" 0 1 2 3 15
	local uboot_name=${CHOSEN_UBOOT}_${REVISION}_${ARCH}
	rm -rf $uboottempdir/$uboot_name
	mkdir -p $uboottempdir/$uboot_name/usr/lib/{u-boot,$uboot_name} $uboottempdir/$uboot_name/DEBIAN

	# process compilation for one or multiple targets
	while read -r target; do
		local target_make target_patchdir target_files
		target_make=$(cut -d';' -f1 <<< "${target}")
		target_patchdir=$(cut -d';' -f2 <<< "${target}")
		target_files=$(cut -d';' -f3 <<< "${target}")

		# needed for multiple targets and for calling compile_uboot directly
		display_alert "Checking out to clean sources"
		improved_git checkout -f -q HEAD

		if [[ $CLEAN_LEVEL == *make* ]]; then
			display_alert "Cleaning" "$BOOTSOURCEDIR" "info"
			(cd "${SRC}/cache/sources/${BOOTSOURCEDIR}"; make clean > /dev/null 2>&1)
		fi

		advanced_patch "u-boot" "$BOOTPATCHDIR" "$BOARD" "$target_patchdir" "$BRANCH" "${LINUXFAMILY}-${BOARD}-${BRANCH}"

		# create patch for manual source changes
		[[ $CREATE_PATCHES == yes ]] && userpatch_create "u-boot"

		if [[ -n $ATFSOURCE ]]; then
			cp -Rv "${atftempdir}"/*.bin .
			cp -Rv "${atftempdir}"/*.elf .
			rm -rf "${atftempdir}"
		fi

		echo -e "\n\t== u-boot make $BOOTCONFIG ==\n" >> "${DEST}"/${LOG_SUBPATH}/compilation.log
		eval CCACHE_BASEDIR="$(pwd)" env PATH="${toolchain}:${toolchain2}:${PATH}" \
			'make $CTHREADS $BOOTCONFIG \
			CROSS_COMPILE="$CCACHE $UBOOT_COMPILER"' 2>> "${DEST}"/${LOG_SUBPATH}/compilation.log \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/compilation.log'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		# armbian specifics u-boot settings
		[[ -f .config ]] && sed -i 's/CONFIG_LOCALVERSION=""/CONFIG_LOCALVERSION="-armbian"/g' .config
		[[ -f .config ]] && sed -i 's/CONFIG_LOCALVERSION_AUTO=.*/# CONFIG_LOCALVERSION_AUTO is not set/g' .config

		# for modern kernel and non spi targets
		if [[ ${BOOTBRANCH} =~ ^tag:v201[8-9](.*) && ${target} != "spi" && -f .config ]]; then

			sed -i 's/^.*CONFIG_ENV_IS_IN_FAT.*/# CONFIG_ENV_IS_IN_FAT is not set/g' .config
			sed -i 's/^.*CONFIG_ENV_IS_IN_EXT4.*/CONFIG_ENV_IS_IN_EXT4=y/g' .config
			sed -i 's/^.*CONFIG_ENV_IS_IN_MMC.*/# CONFIG_ENV_IS_IN_MMC is not set/g' .config
			sed -i 's/^.*CONFIG_ENV_IS_NOWHERE.*/# CONFIG_ENV_IS_NOWHERE is not set/g' .config | echo \
			"# CONFIG_ENV_IS_NOWHERE is not set" >> .config
			echo 'CONFIG_ENV_EXT4_INTERFACE="mmc"' >> .config
			echo 'CONFIG_ENV_EXT4_DEVICE_AND_PART="0:auto"' >> .config
			echo 'CONFIG_ENV_EXT4_FILE="/boot/boot.env"' >> .config

		fi

		[[ -f tools/logos/udoo.bmp ]] && cp "${SRC}"/packages/blobs/splash/udoo.bmp tools/logos/udoo.bmp
		touch .scmversion

		# $BOOTDELAY can be set in board family config, ensure autoboot can be stopped even if set to 0
		[[ $BOOTDELAY == 0 ]] && echo -e "CONFIG_ZERO_BOOTDELAY_CHECK=y" >> .config
		[[ -n $BOOTDELAY ]] && sed -i "s/^CONFIG_BOOTDELAY=.*/CONFIG_BOOTDELAY=${BOOTDELAY}/" .config || [[ -f .config ]] && echo "CONFIG_BOOTDELAY=${BOOTDELAY}" >> .config

		# workaround when two compilers are needed
		cross_compile="CROSS_COMPILE=$CCACHE $UBOOT_COMPILER";
		[[ -n $UBOOT_TOOLCHAIN2 ]] && cross_compile="ARMBIAN=foe"; # empty parameter is not allowed

		echo -e "\n\t== u-boot make $target_make ==\n" >> "${DEST}"/${LOG_SUBPATH}/compilation.log
		eval CCACHE_BASEDIR="$(pwd)" env PATH="${toolchain}:${toolchain2}:${PATH}" \
			'make $target_make $CTHREADS \
			"${cross_compile}"' 2>>"${DEST}"/${LOG_SUBPATH}/compilation.log \
			${PROGRESS_LOG_TO_FILE:+' | tee -a "${DEST}"/${LOG_SUBPATH}/compilation.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Compiling u-boot..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 ]] && exit_with_error "U-boot compilation failed"

		[[ $(type -t uboot_custom_postprocess) == function ]] && uboot_custom_postprocess

		# copy files to build directory
		for f in $target_files; do
			local f_src
			f_src=$(cut -d':' -f1 <<< "${f}")
			if [[ $f == *:* ]]; then
				local f_dst
				f_dst=$(cut -d':' -f2 <<< "${f}")
			else
				local f_dst
				f_dst=$(basename "${f_src}")
			fi
			[[ ! -f $f_src ]] && exit_with_error "U-boot file not found" "$(basename "${f_src}")"
			cp "${f_src}" "$uboottempdir/${uboot_name}/usr/lib/${uboot_name}/${f_dst}"
		done
	done <<< "$UBOOT_TARGET_MAP"

	# set up postinstall script
	if [[ $BOARD == tinkerboard ]]; then
		cat <<-EOF > "$uboottempdir/${uboot_name}/DEBIAN/postinst"
		#!/bin/bash
		source /usr/lib/u-boot/platform_install.sh
		[[ \$DEVICE == /dev/null ]] && exit 0
		if [[ -z \$DEVICE ]]; then
			DEVICE="/dev/mmcblk0"
			# proceed to other options.
			[ ! -b \$DEVICE ] && DEVICE="/dev/mmcblk1"
			[ ! -b \$DEVICE ] && DEVICE="/dev/mmcblk2"
		fi
		[[ \$(type -t setup_write_uboot_platform) == function ]] && setup_write_uboot_platform
		if [[ -b \$DEVICE ]]; then
			echo "Updating u-boot on \$DEVICE" >&2
			write_uboot_platform \$DIR \$DEVICE
			sync
		else
			echo "Device \$DEVICE does not exist, skipping" >&2
		fi
		exit 0
		EOF
		chmod 755 "$uboottempdir/${uboot_name}/DEBIAN/postinst"
	fi

	# declare -f on non-defined function does not do anything
	cat <<-EOF > "$uboottempdir/${uboot_name}/usr/lib/u-boot/platform_install.sh"
	DIR=/usr/lib/$uboot_name
	$(declare -f write_uboot_platform)
	$(declare -f write_uboot_platform_mtd)
	$(declare -f setup_write_uboot_platform)
	EOF

	# set up control file
	cat <<-EOF > "$uboottempdir/${uboot_name}/DEBIAN/control"
	Package: linux-u-boot-${BOARD}-${BRANCH}
	Version: $REVISION
	Architecture: $ARCH
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Section: kernel
	Priority: optional
	Provides: armbian-u-boot
	Replaces: armbian-u-boot
	Conflicts: armbian-u-boot, u-boot-sunxi
	Description: Uboot loader $version
	EOF

	# copy config file to the package
	# useful for FEL boot with overlayfs_wrapper
	[[ -f .config && -n $BOOTCONFIG ]] && cp .config "$uboottempdir/${uboot_name}/usr/lib/u-boot/${BOOTCONFIG}"
	# copy license files from typical locations
	[[ -f COPYING ]] && cp COPYING "$uboottempdir/${uboot_name}/usr/lib/u-boot/LICENSE"
	[[ -f Licenses/README ]] && cp Licenses/README "$uboottempdir/${uboot_name}/usr/lib/u-boot/LICENSE"
	[[ -n $atftempdir && -f $atftempdir/license.md ]] && cp "${atftempdir}/license.md" "$uboottempdir/${uboot_name}/usr/lib/u-boot/LICENSE.atf"

	display_alert "Building deb" "${uboot_name}.deb" "info"
	fakeroot dpkg-deb -b -Z${DEB_COMPRESS} "$uboottempdir/${uboot_name}" "$uboottempdir/${uboot_name}.deb" >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1
	rm -rf "$uboottempdir/${uboot_name}"
	[[ -n $atftempdir ]] && rm -rf "${atftempdir}"

	[[ ! -f $uboottempdir/${uboot_name}.deb ]] && exit_with_error "Building u-boot package failed"

	rsync --remove-source-files -rq "$uboottempdir/${uboot_name}.deb" "${DEB_STORAGE}/"
	rm -rf "$uboottempdir"
}

create_linux-source_package ()
{
	ts=$(date +%s)
	local sources_pkg_dir tmp_src_dir
	tmp_src_dir=$(mktemp -d)
	trap "ret=\$?; rm -rf \"${tmp_src_dir}\" ; exit \$ret" 0 1 2 3 15
	sources_pkg_dir=${tmp_src_dir}/${CHOSEN_KSRC}_${REVISION}_all
	mkdir -p "${sources_pkg_dir}"/usr/src/ \
		"${sources_pkg_dir}"/usr/share/doc/linux-source-${version}-${LINUXFAMILY} \
		"${sources_pkg_dir}"/DEBIAN

	cp "${SRC}/config/kernel/${LINUXCONFIG}.config" "default_${LINUXCONFIG}.config"
	xz < .config > "${sources_pkg_dir}/usr/src/${LINUXCONFIG}_${version}_${REVISION}_config.xz"

	display_alert "Compressing sources for the linux-source package"
	tar cp --directory="$kerneldir" --exclude='.git' --owner=root . \
		| pv -p -b -r -s "$(du -sb "$kerneldir" --exclude=='.git' | cut -f1)" \
		| pixz -4 > "${sources_pkg_dir}/usr/src/linux-source-${version}-${LINUXFAMILY}.tar.xz"
	cp COPYING "${sources_pkg_dir}/usr/share/doc/linux-source-${version}-${LINUXFAMILY}/LICENSE"

	cat <<-EOF > "${sources_pkg_dir}"/DEBIAN/control
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

	fakeroot dpkg-deb -b -Z${DEB_COMPRESS} -z0 "${sources_pkg_dir}" "${sources_pkg_dir}.deb"
	rsync --remove-source-files -rq "${sources_pkg_dir}.deb" "${DEB_STORAGE}/"

	te=$(date +%s)
	display_alert "Make the linux-source package" "$(($te - $ts)) sec." "info"
	rm -rf "${tmp_src_dir}"
}

compile_kernel()
{
	if [[ $CLEAN_LEVEL == *make* ]]; then
		display_alert "Cleaning" "$LINUXSOURCEDIR" "info"
		(cd "${SRC}/cache/sources/${LINUXSOURCEDIR}"; make ARCH="${ARCHITECTURE}" clean >/dev/null 2>&1)
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

	# kernel package name extension
	NAME_EXTENSION="${NAME_EXTENSION:-${BRANCH}-$LINUXFAMILY}"

	KDEB_PKGVERSION=${version}-${VENDOR}.${REVISION%-*}

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
		KDEB_PKGVERSION=$KDEB_PKGVERSION \
		KDEB_COMPRESS=${DEB_COMPRESS} \
		NAME_EXTENSION=$NAME_EXTENSION \
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

	rsync --remove-source-files -rq ./*.deb "${DEB_STORAGE}/" || exit_with_error "Failed moving kernel DEBs"

	# store git hash to the file and create a change log
	HASHTARGET="${SRC}/cache/hash"$([[ ${BETA} == yes ]] && echo "-beta")"/linux-image-${BRANCH}-${LINUXFAMILY}"
	OLDHASHTARGET=$(head -1 "${HASHTARGET}.githash" 2>/dev/null)

	# check if OLDHASHTARGET commit exists otherwise use oldest
	if  [[ -z ${KERNEL_VERSION_LEVEL} ]]; then
		git -C ${kerneldir} cat-file -t ${OLDHASHTARGET} >/dev/null 2>&1
		[[ $? -ne 0 ]] && OLDHASHTARGET=$(git -C ${kerneldir} show HEAD~199 --pretty=format:"%H" --no-patch)
	else
		git -C ${kerneldir} cat-file -t ${OLDHASHTARGET} >/dev/null 2>&1
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




compile_firmware()
{
	display_alert "Merging and packaging linux firmware" "@host" "info"

	local firmwaretempdir plugin_dir

	firmwaretempdir=$(mktemp -d)
	chmod 700 ${firmwaretempdir}
	trap "ret=\$?; rm -rf \"${firmwaretempdir}\" ; exit \$ret" 0 1 2 3 15
	plugin_dir="armbian-firmware${FULL}"
	mkdir -p "${firmwaretempdir}/${plugin_dir}/lib/firmware"

	fetch_from_repo "$GITHUB_SOURCE/armbian/firmware" "armbian-firmware-git" "branch:master"
	if [[ -n $FULL ]]; then
		fetch_from_repo "$MAINLINE_FIRMWARE_SOURCE" "linux-firmware-git" "branch:main"
		# cp : create hardlinks
		cp -af --reflink=auto "${SRC}"/cache/sources/linux-firmware-git/* "${firmwaretempdir}/${plugin_dir}/lib/firmware/"
	fi
	# overlay our firmware
	# cp : create hardlinks
	cp -af --reflink=auto "${SRC}"/cache/sources/armbian-firmware-git/* "${firmwaretempdir}/${plugin_dir}/lib/firmware/"

	rm -rf "${firmwaretempdir}/${plugin_dir}"/lib/firmware/.git
	cd "${firmwaretempdir}/${plugin_dir}" || exit

	# set up control file
	mkdir -p DEBIAN
	cat <<-END > DEBIAN/control
	Package: armbian-firmware${FULL}
	Version: $REVISION
	Architecture: all
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Replaces: linux-firmware, firmware-brcm80211, firmware-ralink, firmware-samsung, firmware-realtek, armbian-firmware${REPLACE}
	Section: kernel
	Priority: optional
	Description: Linux firmware${FULL}
	END

	cd "${firmwaretempdir}" || exit
	# pack
	mv "armbian-firmware${FULL}" "armbian-firmware${FULL}_${REVISION}_all"
	display_alert "Building firmware package" "armbian-firmware${FULL}_${REVISION}_all" "info"
	fakeroot dpkg-deb -b -Z${DEB_COMPRESS} "armbian-firmware${FULL}_${REVISION}_all" >> "${DEST}"/${LOG_SUBPATH}/install.log 2>&1
	mv "armbian-firmware${FULL}_${REVISION}_all" "armbian-firmware${FULL}"
	rsync -rq "armbian-firmware${FULL}_${REVISION}_all.deb" "${DEB_STORAGE}/"

	# remove temp directory
	rm -rf "${firmwaretempdir}"
}




compile_armbian-zsh()
{

	local tmp_dir armbian_zsh_dir
	tmp_dir=$(mktemp -d)
	chmod 700 ${tmp_dir}
	trap "ret=\$?; rm -rf \"${tmp_dir}\" ; exit \$ret" 0 1 2 3 15
	armbian_zsh_dir=armbian-zsh_${REVISION}_all
	display_alert "Building deb" "armbian-zsh" "info"

	fetch_from_repo "$GITHUB_SOURCE/ohmyzsh/ohmyzsh" "oh-my-zsh" "branch:master"
	fetch_from_repo "$GITHUB_SOURCE/mroth/evalcache" "evalcache" "branch:master"

	mkdir -p "${tmp_dir}/${armbian_zsh_dir}"/{DEBIAN,etc/skel/,etc/oh-my-zsh/,/etc/skel/.oh-my-zsh/cache}

	# set up control file
	cat <<-END > "${tmp_dir}/${armbian_zsh_dir}"/DEBIAN/control
	Package: armbian-zsh
	Version: $REVISION
	Architecture: all
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Depends: zsh, tmux
	Section: utils
	Priority: optional
	Description: Armbian improved ZShell
	END

	# set up post install script
	cat <<-END > "${tmp_dir}/${armbian_zsh_dir}"/DEBIAN/postinst
	#!/bin/sh

	# copy cache directory if not there yet
	awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$6"/.oh-my-zsh"}' /etc/passwd | xargs -i sh -c 'test ! -d {} && cp -R --attributes-only /etc/skel/.oh-my-zsh {}'
	awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$6"/.zshrc"}' /etc/passwd | xargs -i sh -c 'test ! -f {} && cp -R /etc/skel/.zshrc {}'

	# fix owner permissions in home directory
	awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$1":"\$3" "\$6"/.oh-my-zsh"}' /etc/passwd | xargs -n2 chown -R
	awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$1":"\$3" "\$6"/.zshrc"}' /etc/passwd | xargs -n2 chown -R

	# add support for bash profile
	! grep emulate /etc/zsh/zprofile  >/dev/null && echo "emulate sh -c 'source /etc/profile'" >> /etc/zsh/zprofile
	exit 0
	END

	cp -R "${SRC}"/cache/sources/oh-my-zsh "${tmp_dir}/${armbian_zsh_dir}"/etc/
	cp -R "${SRC}"/cache/sources/evalcache "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/plugins
	cp "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/templates/zshrc.zsh-template "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	chmod -R g-w,o-w "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/

	# we have common settings
	sed -i "s/^export ZSH=.*/export ZSH=\/etc\/oh-my-zsh/" "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# user cache
	sed -i "/^export ZSH=.*/a export ZSH_CACHE_DIR=~\/.oh-my-zsh\/cache" "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# define theme
	sed -i 's/^ZSH_THEME=.*/ZSH_THEME="mrtazz"/' "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# disable auto update since we provide update via package
	sed -i "s/^# zstyle ':omz:update' mode disabled.*/zstyle ':omz:update' mode disabled/g" "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# define default plugins
	sed -i 's/^plugins=.*/plugins=(evalcache git git-extras debian tmux screen history extract colorize web-search docker)/' "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	chmod 755 "${tmp_dir}/${armbian_zsh_dir}"/DEBIAN/postinst

	fakeroot dpkg-deb -b -Z${DEB_COMPRESS} "${tmp_dir}/${armbian_zsh_dir}" >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1
	rsync --remove-source-files -rq "${tmp_dir}/${armbian_zsh_dir}.deb" "${DEB_STORAGE}/"
	rm -rf "${tmp_dir}"

}




compile_armbian-config()
{

	local tmp_dir armbian_config_dir
	tmp_dir=$(mktemp -d)
	chmod 700 ${tmp_dir}
	trap "ret=\$?; rm -rf \"${tmp_dir}\" ; exit \$ret" 0 1 2 3 15
	armbian_config_dir=armbian-config_${REVISION}_all
	display_alert "Building deb" "armbian-config" "info"

	fetch_from_repo "$GITHUB_SOURCE/armbian/config" "armbian-config" "branch:master"
	fetch_from_repo "$GITHUB_SOURCE/dylanaraps/neofetch" "neofetch" "tag:7.1.0"
	fetch_from_repo "$GITHUB_SOURCE/complexorganizations/wireguard-manager" "wireguard-manager" "tag:v1.0.0.10-26-2021"

	mkdir -p "${tmp_dir}/${armbian_config_dir}"/{DEBIAN,usr/bin/,usr/sbin/,usr/lib/armbian-config/}

	# set up control file
	cat <<-END > "${tmp_dir}/${armbian_config_dir}"/DEBIAN/control
	Package: armbian-config
	Version: $REVISION
	Architecture: all
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Replaces: armbian-bsp, neofetch
	Depends: bash, iperf3, psmisc, curl, bc, expect, dialog, pv, zip, \
	debconf-utils, unzip, build-essential, html2text, html2text, dirmngr, software-properties-common, debconf, jq
	Recommends: armbian-bsp
	Suggests: libpam-google-authenticator, qrencode, network-manager, sunxi-tools
	Section: utils
	Priority: optional
	Description: Armbian configuration utility
	END

	install -m 755 "${SRC}"/cache/sources/neofetch/neofetch "${tmp_dir}/${armbian_config_dir}"/usr/bin/neofetch
	cd "${tmp_dir}/${armbian_config_dir}"/usr/bin/
	process_patch_file "${SRC}/patch/misc/add-armbian-neofetch.patch" "applying"

	install -m 755 "${SRC}"/cache/sources/wireguard-manager/wireguard-manager.sh "${tmp_dir}/${armbian_config_dir}"/usr/bin/wireguard-manager
	install -m 755 "${SRC}"/cache/sources/armbian-config/scripts/tv_grab_file "${tmp_dir}/${armbian_config_dir}"/usr/bin/tv_grab_file
	install -m 755 "${SRC}"/cache/sources/armbian-config/debian-config "${tmp_dir}/${armbian_config_dir}"/usr/sbin/armbian-config
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-jobs "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/jobs.sh
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-submenu "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/submenu.sh
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-functions "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/functions.sh
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-functions-network "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/functions-network.sh
	install -m 755 "${SRC}"/cache/sources/armbian-config/softy "${tmp_dir}/${armbian_config_dir}"/usr/sbin/softy
	# fallback to replace armbian-config in BSP
	ln -sf /usr/sbin/armbian-config "${tmp_dir}/${armbian_config_dir}"/usr/bin/armbian-config
	ln -sf /usr/sbin/softy "${tmp_dir}/${armbian_config_dir}"/usr/bin/softy

	fakeroot dpkg-deb -b -Z${DEB_COMPRESS} "${tmp_dir}/${armbian_config_dir}" >/dev/null
	rsync --remove-source-files -rq "${tmp_dir}/${armbian_config_dir}.deb" "${DEB_STORAGE}/"
	rm -rf "${tmp_dir}"
}





compile_xilinx_bootgen()
{
	# Source code checkout
	(fetch_from_repo "$GITHUB_SOURCE/Xilinx/bootgen.git" "xilinx-bootgen" "branch:master")

	pushd "${SRC}"/cache/sources/xilinx-bootgen || exit

	# Compile and install only if git commit hash changed
	# need to check if /usr/local/bin/bootgen to detect new Docker containers with old cached sources
	if [[ ! -f .commit_id || $(improved_git rev-parse @ 2>/dev/null) != $(<.commit_id) || ! -f /usr/local/bin/bootgen ]]; then
		display_alert "Compiling" "xilinx-bootgen" "info"
		make -s clean >/dev/null
		make -s -j$(nproc) bootgen >/dev/null
		mkdir -p /usr/local/bin/
		install bootgen /usr/local/bin >/dev/null 2>&1
		improved_git rev-parse @ 2>/dev/null > .commit_id
	fi

	popd
}

grab_version()
{
	local ver=()
	ver[0]=$(grep "^VERSION" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+')
	ver[1]=$(grep "^PATCHLEVEL" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+')
	ver[2]=$(grep "^SUBLEVEL" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^[[:digit:]]+')
	ver[3]=$(grep "^EXTRAVERSION" "${1}"/Makefile | head -1 | awk '{print $(NF)}' | grep -oE '^-rc[[:digit:]]+')
	echo "${ver[0]:-0}${ver[1]:+.${ver[1]}}${ver[2]:+.${ver[2]}}${ver[3]}"
}

# find_toolchain <compiler_prefix> <expression>
#
# returns path to toolchain that satisfies <expression>
#
find_toolchain()
{
	[[ "${SKIP_EXTERNAL_TOOLCHAINS}" == "yes" ]] && { echo "/usr/bin"; return; }
	local compiler=$1
	local expression=$2
	local dist=10
	local toolchain=""
	# extract target major.minor version from expression
	local target_ver
	target_ver=$(grep -oE "[[:digit:]]+\.[[:digit:]]" <<< "$expression")
	for dir in "${SRC}"/cache/toolchain/*/; do
		# check if is a toolchain for current $ARCH
		[[ ! -f ${dir}bin/${compiler}gcc ]] && continue
		# get toolchain major.minor version
		local gcc_ver
		gcc_ver=$("${dir}bin/${compiler}gcc" -dumpversion | grep -oE "^[[:digit:]]+\.[[:digit:]]")
		# check if toolchain version satisfies requirement
		awk "BEGIN{exit ! ($gcc_ver $expression)}" >/dev/null || continue
		# check if found version is the closest to target
		# may need different logic here with more than 1 digit minor version numbers
		# numbers: 3.9 > 3.10; versions: 3.9 < 3.10
		# dpkg --compare-versions can be used here if operators are changed
		local d
		d=$(awk '{x = $1 - $2}{printf "%.1f\n", (x > 0) ? x : -x}' <<< "$target_ver $gcc_ver")
		if awk "BEGIN{exit ! ($d < $dist)}" >/dev/null ; then
			dist=$d
			toolchain=${dir}bin
		fi
	done
	echo "$toolchain"
	# logging a stack of used compilers.
	if [[ -f "${DEST}"/${LOG_SUBPATH}/compiler.log ]]; then
		if ! grep -q "$toolchain" "${DEST}"/${LOG_SUBPATH}/compiler.log; then
			echo "$toolchain" >> "${DEST}"/${LOG_SUBPATH}/compiler.log;
		fi
	else
			echo "$toolchain" >> "${DEST}"/${LOG_SUBPATH}/compiler.log;
	fi
}

# advanced_patch <dest> <family> <board> <target> <branch> <description>
#
# parameters:
# <dest>: u-boot, kernel, atf
# <family>: u-boot: u-boot, u-boot-neo; kernel: sun4i-default, sunxi-next, ...
# <board>: cubieboard, cubieboard2, cubietruck, ...
# <target>: optional subdirectory
# <description>: additional description text
#
# priority:
# $USERPATCHES_PATH/<dest>/<family>/target_<target>
# $USERPATCHES_PATH/<dest>/<family>/board_<board>
# $USERPATCHES_PATH/<dest>/<family>/branch_<branch>
# $USERPATCHES_PATH/<dest>/<family>
# $SRC/patch/<dest>/<family>/target_<target>
# $SRC/patch/<dest>/<family>/board_<board>
# $SRC/patch/<dest>/<family>/branch_<branch>
# $SRC/patch/<dest>/<family>
#
advanced_patch()
{
	local dest=$1
	local family=$2
	local board=$3
	local target=$4
	local branch=$5
	local description=$6

	display_alert "Started patching process for" "$dest $description" "info"
	display_alert "Looking for user patches in" "userpatches/$dest/$family" "info"

	local names=()
	local dirs=(
		"$USERPATCHES_PATH/$dest/$family/target_${target}:[\e[33mu\e[0m][\e[34mt\e[0m]"
		"$USERPATCHES_PATH/$dest/$family/board_${board}:[\e[33mu\e[0m][\e[35mb\e[0m]"
		"$USERPATCHES_PATH/$dest/$family/branch_${branch}:[\e[33mu\e[0m][\e[33mb\e[0m]"
		"$USERPATCHES_PATH/$dest/$family:[\e[33mu\e[0m][\e[32mc\e[0m]"
		"$SRC/patch/$dest/$family/target_${target}:[\e[32ml\e[0m][\e[34mt\e[0m]"
		"$SRC/patch/$dest/$family/board_${board}:[\e[32ml\e[0m][\e[35mb\e[0m]"
		"$SRC/patch/$dest/$family/branch_${branch}:[\e[32ml\e[0m][\e[33mb\e[0m]"
		"$SRC/patch/$dest/$family:[\e[32ml\e[0m][\e[32mc\e[0m]"
		)
	local links=()

	# required for "for" command
	shopt -s nullglob dotglob
	# get patch file names
	for dir in "${dirs[@]}"; do
		for patch in ${dir%%:*}/*.patch; do
			names+=($(basename "${patch}"))
		done
		# add linked patch directories
		if [[ -d ${dir%%:*} ]]; then
			local findlinks
			findlinks=$(find "${dir%%:*}" -maxdepth 1 -type l -print0 2>&1 | xargs -0)
			[[ -n $findlinks ]] && readarray -d '' links < <(find "${findlinks}" -maxdepth 1 -type f -follow -print -iname "*.patch" -print | grep "\.patch$" | sed "s|${dir%%:*}/||g" 2>&1)
		fi
	done
	# merge static and linked
	names=("${names[@]}" "${links[@]}")
	# remove duplicates
	local names_s=($(echo "${names[@]}" | tr ' ' '\n' | LC_ALL=C sort -u | tr '\n' ' '))
	# apply patches
	for name in "${names_s[@]}"; do
		for dir in "${dirs[@]}"; do
			if [[ -f ${dir%%:*}/$name ]]; then
				if [[ -s ${dir%%:*}/$name ]]; then
					process_patch_file "${dir%%:*}/$name" "${dir##*:}"
				else
					display_alert "* ${dir##*:} $name" "skipped"
				fi
				break # next name
			fi
		done
	done
}

# process_patch_file <file> <description>
#
# parameters:
# <file>: path to patch file
# <status>: additional status text
#
process_patch_file()
{
	local patch=$1
	local status=$2

	# detect and remove files which patch will create
	lsdiff -s --strip=1 "${patch}" | grep '^+' | awk '{print $2}' | xargs -I % sh -c 'rm -f %'

	echo "Processing file $patch" >> "${DEST}"/${LOG_SUBPATH}/patching.log
	patch --batch --silent -p1 -N < "${patch}" >> "${DEST}"/${LOG_SUBPATH}/patching.log 2>&1

	if [[ $? -ne 0 ]]; then
		display_alert "* $status $(basename "${patch}")" "failed" "wrn"
		[[ $EXIT_PATCHING_ERROR == yes ]] && exit_with_error "Aborting due to" "EXIT_PATCHING_ERROR"
	else
		display_alert "* $status $(basename "${patch}")" "" "info"
	fi
	echo >> "${DEST}"/${LOG_SUBPATH}/patching.log
}


# apply_patch_series <target dir> <full path to series file>
apply_patch_series ()
{
	local t_dir="${1}"
	local series="${2}"
	local bzdir="$(dirname $series)"
	local flag
	local err_pt=$(mktemp /tmp/apply_patch_series_XXXXX)

	list=$(awk '$0 !~ /^#.*|^-.*|^$/' "${series}")
	skiplist=$(awk '$0 ~ /^-.*/{print $NF}' "${series}")

	display_alert "apply a series of " "[$(echo $list | wc -w)] patches"
	display_alert "skip [$(echo $skiplist | wc -w)] patches"

	cd "${t_dir}" || exit 1
	for p in $list
	do
		# Detect and remove files as '*.patch' which patch will create.
		# So we need to delete the file before applying the patch if it exists.
		lsdiff -s --strip=1 "$bzdir/$p" | \
		awk '$0 ~ /^+.*patch$/{print $2}' | \
		xargs -I % sh -c 'rm -f %'

		patch --batch --silent --no-backup-if-mismatch -p1 -N < $bzdir/"$p" >>$err_pt 2>&1
		flag=$?


		case $flag in
			0)	printf "[\033[32m done \033[0m]    %s\n" "${p}"
				printf "[ done ]    %s\n" "${p}" >> "${DEST}"/debug/patching.log
				;;
			1)
				printf "[\033[33m FAILED \033[0m]  %s\n" "${p}"
				echo -e "[ FAILED ]  For ${p} \t\tprocess exit [ $flag ]" >>"${DEST}"/debug/patching.log
				cat $err_pt >>"${DEST}"/debug/patching.log
				;;
			2)
				printf "[\033[31m Patch wrong \033[0m] %s\n" "${p}"
				echo -e "Patch wrong ${p}\t\tprocess exit [ $flag ]" >>"${DEST}"/debug/patching.log
				cat $err_pt >>"${DEST}"/debug/patching.log
				;;
		esac
		echo "" >$err_pt
	done
	echo "" >>"${DEST}"/debug/patching.log
	rm $err_pt
}

userpatch_create()
{
	# create commit to start from clean source
	git add .
	git -c user.name='Armbian User' -c user.email='user@example.org' commit -q -m "Cleaning working copy"

	local patch="$DEST/patch/$1-$LINUXFAMILY-$BRANCH.patch"

	# apply previous user debug mode created patches
	if [[ -f $patch ]]; then
		display_alert "Applying existing $1 patch" "$patch" "wrn" && patch --batch --silent -p1 -N < "${patch}"
		# read title of a patch in case Git is configured
		if [[ -n $(git config user.email) ]]; then
			COMMIT_MESSAGE=$(cat "${patch}" | grep Subject | sed -n -e '0,/PATCH/s/.*PATCH]//p' | xargs)
			display_alert "Patch name extracted" "$COMMIT_MESSAGE" "wrn"
		fi
	fi

	# prompt to alter source
	display_alert "Make your changes in this directory:" "$(pwd)" "wrn"
	display_alert "Press <Enter> after you are done" "waiting" "wrn"
	read -r </dev/tty
	tput cuu1
	git add .
	# create patch out of changes
	if ! git diff-index --quiet --cached HEAD; then
		# If Git is configured, create proper patch and ask for a name
		if [[ -n $(git config user.email) ]]; then
			display_alert "Add / change patch name" "$COMMIT_MESSAGE" "wrn"
			read -e -p "Patch description: " -i "$COMMIT_MESSAGE" COMMIT_MESSAGE
			[[ -z "$COMMIT_MESSAGE" ]] && COMMIT_MESSAGE="Patching something"
			git commit -s -m "$COMMIT_MESSAGE"
			git format-patch -1 HEAD --stdout --signature="Created with Armbian build tools $GITHUB_SOURCE/armbian/build" > "${patch}"
			PATCHFILE=$(git format-patch -1 HEAD)
			rm $PATCHFILE # delete the actual file
			# create a symlink to have a nice name ready
			find $DEST/patch/ -type l -delete # delete any existing
			ln -sf $patch $DEST/patch/$PATCHFILE
		else
			git diff --staged > "${patch}"
		fi
		display_alert "You will find your patch here:" "$patch" "info"
	else
		display_alert "No changes found, skipping patch creation" "" "wrn"
	fi
	git reset --soft HEAD~
	for i in {3..1..1}; do echo -n "$i." && sleep 1; done
}

# overlayfs_wrapper <operation> <workdir> <description>
#
# <operation>: wrap|cleanup
# <workdir>: path to source directory
# <description>: suffix for merged directory to help locating it in /tmp
# return value: new directory
#
# Assumptions/notes:
# - Ubuntu Xenial host
# - /tmp is mounted as tmpfs
# - there is enough space on /tmp
# - UB if running multiple compilation tasks in parallel
# - should not be used with CREATE_PATCHES=yes
#
overlayfs_wrapper()
{
	local operation="$1"
	if [[ $operation == wrap ]]; then
		local srcdir="$2"
		local description="$3"
		mkdir -p /tmp/overlay_components/ /tmp/armbian_build/
		local tempdir workdir mergeddir
		tempdir=$(mktemp -d --tmpdir="/tmp/overlay_components/")
		workdir=$(mktemp -d --tmpdir="/tmp/overlay_components/")
		mergeddir=$(mktemp -d --suffix="_$description" --tmpdir="/tmp/armbian_build/")
		mount -t overlay overlay -o lowerdir="$srcdir",upperdir="$tempdir",workdir="$workdir" "$mergeddir"
		# this is executed in a subshell, so use temp files to pass extra data outside
		echo "$tempdir" >> /tmp/.overlayfs_wrapper_cleanup
		echo "$mergeddir" >> /tmp/.overlayfs_wrapper_umount
		echo "$mergeddir" >> /tmp/.overlayfs_wrapper_cleanup
		echo "$mergeddir"
		return
	fi
	if [[ $operation == cleanup ]]; then
		if [[ -f /tmp/.overlayfs_wrapper_umount ]]; then
			for dir in $(</tmp/.overlayfs_wrapper_umount); do
				[[ $dir == /tmp/* ]] && umount -l "$dir" > /dev/null 2>&1
			done
		fi
		if [[ -f /tmp/.overlayfs_wrapper_cleanup ]]; then
			for dir in $(</tmp/.overlayfs_wrapper_cleanup); do
				[[ $dir == /tmp/* ]] && rm -rf "$dir"
			done
		fi
		rm -f /tmp/.overlayfs_wrapper_umount /tmp/.overlayfs_wrapper_cleanup
	fi
}
