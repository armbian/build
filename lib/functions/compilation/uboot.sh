# this receives version  target uboot_name uboottempdir uboot_target_counter toolchain as variables.
function compile_uboot_target() {
	local uboot_prefix="{u-boot:${uboot_target_counter}} "

	local target_make target_patchdir target_files
	target_make=$(cut -d';' -f1 <<< "${target}")
	target_patchdir=$(cut -d';' -f2 <<< "${target}")
	target_files=$(cut -d';' -f3 <<< "${target}")

	# needed for multiple targets and for calling compile_uboot directly
	display_alert "${uboot_prefix} Checking out to clean sources" "{$BOOTSOURCEDIR} for ${target_make}"
	improved_git checkout -f -q HEAD

	if [[ $CLEAN_LEVEL == *make* ]]; then
		display_alert "${uboot_prefix}Cleaning" "${BOOTSOURCEDIR}" "info"
		(
			cd "${SRC}/cache/sources/${BOOTSOURCEDIR}"
			make clean 2>&1
		)
	fi

	advanced_patch "u-boot" "$BOOTPATCHDIR" "$BOARD" "$target_patchdir" "$BRANCH" "${LINUXFAMILY}-${BOARD}-${BRANCH}"

	# create patch for manual source changes
	[[ $CREATE_PATCHES == yes ]] && userpatch_create "u-boot"

	if [[ -n $ATFSOURCE ]]; then
		cp -Rv "${atftempdir}"/*.bin .
		rm -rf "${atftempdir}"
	fi

	display_alert "${uboot_prefix}Preparing u-boot config" "${version} ${target_make}" "info"
	export MSG_IF_ERROR="${uboot_prefix}Failed to configure u-boot ${version} $BOOTCONFIG ${target_make}"
	run_host_command_logged CCACHE_BASEDIR="$(pwd)" PATH="${toolchain}:${toolchain2}:${PATH}" \
		make "$CTHREADS" "$BOOTCONFIG" "CROSS_COMPILE=\"$CCACHE $UBOOT_COMPILER\"" "KCFLAGS=-fdiagnostics-color=always"

	# armbian specifics u-boot settings
	[[ -f .config ]] && sed -i 's/CONFIG_LOCALVERSION=""/CONFIG_LOCALVERSION="-armbian"/g' .config
	[[ -f .config ]] && sed -i 's/CONFIG_LOCALVERSION_AUTO=.*/# CONFIG_LOCALVERSION_AUTO is not set/g' .config

	# for modern (? 2018-2019?) kernel and non spi targets
	if [[ ${BOOTBRANCH} =~ ^tag:v201[8-9](.*) && ${target} != "spi" && -f .config ]]; then
		sed -i 's/^.*CONFIG_ENV_IS_IN_FAT.*/# CONFIG_ENV_IS_IN_FAT is not set/g' .config
		sed -i 's/^.*CONFIG_ENV_IS_IN_EXT4.*/CONFIG_ENV_IS_IN_EXT4=y/g' .config
		sed -i 's/^.*CONFIG_ENV_IS_IN_MMC.*/# CONFIG_ENV_IS_IN_MMC is not set/g' .config
		sed -i 's/^.*CONFIG_ENV_IS_NOWHERE.*/# CONFIG_ENV_IS_NOWHERE is not set/g' .config
		echo "# CONFIG_ENV_IS_NOWHERE is not set" >> .config
		echo 'CONFIG_ENV_EXT4_INTERFACE="mmc"' >> .config
		echo 'CONFIG_ENV_EXT4_DEVICE_AND_PART="0:auto"' >> .config
		echo 'CONFIG_ENV_EXT4_FILE="/boot/boot.env"' >> .config
	fi

	# @TODO: this does not belong here
	[[ -f tools/logos/udoo.bmp ]] && cp "${SRC}"/packages/blobs/splash/udoo.bmp tools/logos/udoo.bmp

	# @TODO: why?
	touch .scmversion

	# $BOOTDELAY can be set in board family config, ensure autoboot can be stopped even if set to 0
	[[ $BOOTDELAY == 0 ]] && echo -e "CONFIG_ZERO_BOOTDELAY_CHECK=y" >> .config
	[[ -n $BOOTDELAY ]] && sed -i "s/^CONFIG_BOOTDELAY=.*/CONFIG_BOOTDELAY=${BOOTDELAY}/" .config || [[ -f .config ]] && echo "CONFIG_BOOTDELAY=${BOOTDELAY}" >> .config

	# workaround when two compilers are needed
	cross_compile="CROSS_COMPILE=\"$CCACHE $UBOOT_COMPILER\""
	[[ -n $UBOOT_TOOLCHAIN2 ]] && cross_compile="ARMBIAN=foe" # empty parameter is not allowed

	display_alert "${uboot_prefix}Compiling u-boot" "${version} ${target_make}" "info"
	export MSG_IF_ERROR="${uboot_prefix}Failed to build u-boot ${version} ${target_make}"
	run_host_command_logged_long_running CCACHE_BASEDIR="$(pwd)" PATH="${toolchain}:${toolchain2}:${PATH}" make "$target_make" "$CTHREADS" "${cross_compile}" "KCFLAGS=-fdiagnostics-color=always"

	if [[ $(type -t uboot_custom_postprocess) == function ]]; then
		display_alert "${uboot_prefix}Postprocessing u-boot" "${version} ${target_make}"
		uboot_custom_postprocess
	fi

	display_alert "${uboot_prefix}Preparing u-boot targets packaging" "${version} ${target_make}"
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
		display_alert "${uboot_prefix}Deploying u-boot binary target" "${version} ${target_make} :: ${f_dst}"
		[[ ! -f $f_src ]] && exit_with_error "U-boot artifact not found" "$(basename "${f_src}")"
		run_host_command_logged cp -v "${f_src}" "$uboottempdir/${uboot_name}/usr/lib/${uboot_name}/${f_dst}"
		#display_alert "Done with binary target" "${version} ${target_make} :: ${f_dst}"
	done

	display_alert "${uboot_prefix}Done with u-boot target" "${version} ${target_make}"
	return 0
}

compile_uboot() {
	# not optimal, but extra cleaning before overlayfs_wrapper should keep sources directory clean
	if [[ $CLEAN_LEVEL == *make* ]]; then
		display_alert "Cleaning" "$BOOTSOURCEDIR" "info"
		(
			cd "${SRC}/cache/sources/${BOOTSOURCEDIR}"
			make clean > /dev/null 2>&1
		)
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

	display_alert "Compiling u-boot" "$version ${ubootdir}" "info"

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

	local uboot_name="${CHOSEN_UBOOT}_${REVISION}_${ARCH}"

	# create directory structure for the .deb package
	uboottempdir="$(mktemp -d)" # subject to TMPDIR/WORKDIR, so is protected by single/common error trap to clean-up.
	chmod 700 "${uboottempdir}"
	mkdir -p "$uboottempdir/$uboot_name/usr/lib/u-boot" "$uboottempdir/$uboot_name/usr/lib/$uboot_name" "$uboottempdir/$uboot_name/DEBIAN"

	# Try very hard, to fault even, to avoid using subshells while reading a newline-delimited string.
	# Sorry for the juggling with IFS.
	local _old_ifs="${IFS}" _new_ifs=$'\n' uboot_target_counter=1
	IFS="${_new_ifs}" # split on newlines only
	for target in ${UBOOT_TARGET_MAP}; do
		IFS="${_old_ifs}" # restore for the body of loop
		export target uboot_name uboottempdir toolchain version uboot_target_counter
		compile_uboot_target
		uboot_target_counter=$((uboot_target_counter + 1))
		IFS="${_new_ifs}" # split on newlines only for rest of loop
	done
	IFS="${_old_ifs}"

	display_alert "Preparing u-boot general packaging. all_worked:${all_worked}  any_worked:${any_worked} " "${version} ${target_make}"

	# set up postinstall script # @todo: extract into a tinkerboard extension
	if [[ $BOARD == tinkerboard ]]; then
		cat <<- EOF > "$uboottempdir/${uboot_name}/DEBIAN/postinst"
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

	# declare -f on non-defined function does not do anything (but exits with errors, so ignore them with "|| true")
	cat <<- EOF > "$uboottempdir/${uboot_name}/usr/lib/u-boot/platform_install.sh"
		DIR=/usr/lib/$uboot_name
		$(declare -f write_uboot_platform || true)
		$(declare -f write_uboot_platform_mtd || true)
		$(declare -f setup_write_uboot_platform || true)
	EOF

	# set up control file
	cat <<- EOF > "$uboottempdir/${uboot_name}/DEBIAN/control"
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
	[[ -f .config && -n $BOOTCONFIG ]] && cp .config "$uboottempdir/${uboot_name}/usr/lib/u-boot/${BOOTCONFIG}" 2>&1
	# copy license files from typical locations
	[[ -f COPYING ]] && cp COPYING "$uboottempdir/${uboot_name}/usr/lib/u-boot/LICENSE" 2>&1
	[[ -f Licenses/README ]] && cp Licenses/README "$uboottempdir/${uboot_name}/usr/lib/u-boot/LICENSE" 2>&1
	[[ -n $atftempdir && -f $atftempdir/license.md ]] && cp "${atftempdir}/license.md" "$uboottempdir/${uboot_name}/usr/lib/u-boot/LICENSE.atf" 2>&1

	display_alert "Building u-boot deb" "${uboot_name}.deb"
	fakeroot_dpkg_deb_build "$uboottempdir/${uboot_name}" "$uboottempdir/${uboot_name}.deb"
	rm -rf "$uboottempdir/${uboot_name}"
	[[ -n $atftempdir ]] && rm -rf "${atftempdir}"

	[[ ! -f $uboottempdir/${uboot_name}.deb ]] && exit_with_error "Building u-boot package failed"

	rsync --remove-source-files -rq "$uboottempdir/${uboot_name}.deb" "${DEB_STORAGE}/" 2>&1

	display_alert "Built u-boot deb OK" "${uboot_name}.deb" "info"
	return 0 # success
}
