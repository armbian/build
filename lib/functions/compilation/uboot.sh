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
			cp -Rv "${atftempdir}"/*.bin . 2>/dev/null || \
			cp -Rv "${atftempdir}"/*.elf . 2>/dev/null
			[[ $? -ne 0 ]] && exit_with_error "ATF binary not found"
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
