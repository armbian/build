#!/usr/bin/env bash

function maybe_make_clean_uboot() {
	if [[ $CLEAN_LEVEL == *make-uboot* ]]; then
		display_alert "${uboot_prefix}Cleaning u-boot tree - CLEAN_LEVEL contains 'make-uboot'" "${BOOTSOURCEDIR}" "info"
		(
			cd "${SRC}/cache/sources/${BOOTSOURCEDIR}" || exit_with_error "crazy about ${BOOTSOURCEDIR}"
			run_host_command_logged make clean
		)
	else
		display_alert "${uboot_prefix}Not cleaning u-boot tree, use CLEAN_LEVEL=make-uboot if needed" "CLEAN_LEVEL=${CLEAN_LEVEL}" "debug"
	fi
}

# this receives version  target uboot_name uboottempdir uboot_target_counter toolchain as variables.
# also receives uboot_prefix, target_make, target_patchdir, target_files as input
function compile_uboot_target() {
	local uboot_work_dir=""
	uboot_work_dir="$(pwd)"

	# needed for multiple targets and for calling compile_uboot directly
	display_alert "${uboot_prefix} Checking out to clean sources" "{$BOOTSOURCEDIR} for ${target_make}"
	git checkout -f -q HEAD # @TODO: this assumes way too much. should call the wrapper again, not directly

	# grab the prepatch version from Makefile
	local uboot_prepatch_version=""
	uboot_prepatch_version=$(grab_version "${uboot_work_dir}")

	# grab the mtime of the revision.
	declare checked_out_revision_ts="" checked_out_revision_mtime=""
	checked_out_revision_ts="$(git log -1 --pretty=%ct "HEAD")"                         # unix timestamp of the commit date
	checked_out_revision_mtime="$(date +%Y%m%d%H%M%S -d "@${checked_out_revision_ts}")" # convert timestamp to local date/time
	display_alert "u-boot: checked_out_revision_mtime set!" "${checked_out_revision_mtime} - ${checked_out_revision_ts}" "git"

	# mark the minimum mtime for uboot patches
	declare -i patch_minimum_target_mtime="${checked_out_revision_mtime}"
	declare -i patch_dir_mtime="${patch_minimum_target_mtime}"
	local patch_dir="${SRC}/patch/u-boot/${BOOTPATCHDIR}"

	if [[ -d "${patch_dir}" ]]; then
		patch_dir_mtime=$(get_dir_modification_time "${patch_dir}")
		display_alert "uboot: patch_dir mtime:" "${patch_dir_mtime}" "debug"
		patch_minimum_target_mtime=$((patch_dir_mtime > patch_minimum_target_mtime ? patch_dir_mtime : patch_minimum_target_mtime))
		display_alert "uboot: patch_minimum_target_mtime after patch_dir mtime:" "${patch_minimum_target_mtime}" "debug"
	fi

	# @TODO: for u-boot, there's also the BOARD patch directory, which should also be taken into account.

	initialize_fasthash "u-boot-${uboot_target_counter}" "unknown-uboot-hash" "${uboot_prepatch_version}" "$(pwd)"
	fasthash_debug "init"

	maybe_make_clean_uboot

	fasthash_branch "patches-${uboot_target_counter}-${BOOTPATCHDIR}-$BRANCH"
	advanced_patch "u-boot" "$BOOTPATCHDIR" "$BOARD" "$target_patchdir" "$BRANCH" "${LINUXFAMILY}-${BOARD}-${BRANCH}"

	# create patch for manual source changes
	[[ $CREATE_PATCHES == yes ]] && userpatch_create "u-boot"

	# atftempdir comes from atf.sh's compile_atf()
	if [[ -n $ATFSOURCE && -d "${atftempdir}" ]]; then
		display_alert "Copying over bin/elf's from atftempdir" "${atftempdir}" "debug"
		run_host_command_logged cp -pv "${atftempdir}"/*.bin "${atftempdir}"/*.elf ./ # only works due to nullglob
		# atftempdir is under WORKDIR, so no cleanup necessary.
	fi

	display_alert "${uboot_prefix}Preparing u-boot config" "${version} ${target_make}" "info"
	export if_error_detail_message="${uboot_prefix}Failed to configure u-boot ${version} $BOOTCONFIG ${target_make}"
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

	if [[ "${UBOOT_DEBUGGING}" == "yes" ]]; then
		display_alert "Enabling u-boot debugging" "UBOOT_DEBUGGING=yes" "debug"

		# Remove unsets...
		cp .config .config.pre.debug
		cat .config.pre.debug | grep -v -e "CONFIG_LOG is not set" -e "CONFIG_ERRNO_STR" > .config
		rm .config.pre.debug

		# 0 - emergency ; 1 - alert; 2 - critical; 3 - error; 4 - warning; 5 - note; 6 - info; 7 - debug; 8 - debug content; 9 - debug hardware I/O
		cat <<- EXTRA_UBOOT_DEBUG_CONFIGS >> .config
			CONFIG_LOG=y
			CONFIG_LOG_MAX_LEVEL=7
			CONFIG_LOG_DEFAULT_LEVEL=7
			CONFIG_LOG_CONSOLE=y
			CONFIG_SPL_LOG=y
			CONFIG_SPL_LOG_MAX_LEVEL=6
			CONFIG_SPL_LOG_CONSOLE=y
			CONFIG_TPL_LOG=y
			CONFIG_TPL_LOG_MAX_LEVEL=6
			CONFIG_TPL_LOG_CONSOLE=y
			# CONFIG_ERRNO_STR is not set
		EXTRA_UBOOT_DEBUG_CONFIGS

		run_host_command_logged CCACHE_BASEDIR="$(pwd)" PATH="${toolchain}:${toolchain2}:${PATH}" \
			make "olddefconfig" "CROSS_COMPILE=\"$CCACHE $UBOOT_COMPILER\"" "KCFLAGS=-fdiagnostics-color=always"

	fi

	fasthash_debug "finish"
	finish_fasthash "u-boot" # this reports the final hash and creates git branch to build ID. All modifications commited.

	# workaround when two compilers are needed
	cross_compile="CROSS_COMPILE=\"$CCACHE $UBOOT_COMPILER\""
	[[ -n $UBOOT_TOOLCHAIN2 ]] && cross_compile="ARMBIAN=foe" # empty parameter is not allowed

	display_alert "${uboot_prefix}Compiling u-boot" "${version} ${target_make}" "info"
	export if_error_detail_message="${uboot_prefix}Failed to build u-boot ${version} ${target_make}"
	CFLAGS="-fdiagnostics-color=always -Wno-error=maybe-uninitialized -Wno-error=misleading-indentation" \
		KCFLAGS="-fdiagnostics-color=always -Wno-error=maybe-uninitialized -Wno-error=misleading-indentation" \
		run_host_command_logged_long_running CCACHE_BASEDIR="$(pwd)" PATH="${toolchain}:${toolchain2}:${PATH}" \
		make "$target_make" "$CTHREADS" "${cross_compile}"

	if [[ $(type -t uboot_custom_postprocess) == function ]]; then
		display_alert "${uboot_prefix}Postprocessing u-boot" "${version} ${target_make}"
		uboot_custom_postprocess
	fi

	# Hook time, for extra post-processing
	display_alert "Extensions: post_uboot_custom_postprocess" "post_uboot_custom_postprocess" "debug"
	call_extension_method "post_uboot_custom_postprocess" <<- 'POST_UBOOT_CUSTOM_POSTPROCESS'
		*allow extensions to do extra u-boot postprocessing, after uboot_custom_postprocess*
		For hacking at the produced binaries after u-boot is compiled and post-processed.
	POST_UBOOT_CUSTOM_POSTPROCESS

	deploy_built_uboot_bins_for_one_target_to_packaging_area # copy according to the target_files

	display_alert "${uboot_prefix}Done with u-boot target" "${version} ${target_make}"
	return 0
}

function loop_over_uboot_targets_and_do() {
	# Try very hard, to fault even, to avoid using subshells while reading a newline-delimited string.
	# Sorry for the juggling with IFS.
	local _old_ifs="${IFS}" _new_ifs=$'\n' uboot_target_counter=1
	IFS="${_new_ifs}" # split on newlines only
	for target in ${UBOOT_TARGET_MAP}; do
		IFS="${_old_ifs}" # restore for the body of loop
		declare -g target uboot_name uboottempdir toolchain version
		declare -g uboot_prefix="{u-boot:${uboot_target_counter}} "
		declare -g target_make target_patchdir target_files
		target_make=$(cut -d';' -f1 <<< "${target}")
		target_patchdir=$(cut -d';' -f2 <<< "${target}")
		target_files=$(cut -d';' -f3 <<< "${target}")
		# Invoke our parameters directly
		"$@"
		# Increment the counter
		uboot_target_counter=$((uboot_target_counter + 1))
		IFS="${_new_ifs}" # split on newlines only for rest of loop
	done
	IFS="${_old_ifs}"
}

function deploy_built_uboot_bins_for_one_target_to_packaging_area() {
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
		run_host_command_logged cp -v "${f_src}" "${uboottempdir}/${uboot_name}/usr/lib/${uboot_name}/${f_dst}"
		#display_alert "Done with binary target" "${version} ${target_make} :: ${f_dst}"
	done
}

compile_uboot() {
	if [[ -n $BOOTSOURCE ]] && [[ "${BOOTSOURCE}" != "none" ]]; then
		display_alert "Downloading sources" "u-boot" "git"
		GIT_SKIP_SUBMODULES="${UBOOT_GIT_SKIP_SUBMODULES}" fetch_from_repo "$BOOTSOURCE" "$BOOTDIR" "$BOOTBRANCH" "yes" # fetch_from_repo <url> <dir> <ref> <subdir_flag>

		display_alert "Extensions: fetch custom uboot" "fetch_custom_uboot" "debug"
		call_extension_method "fetch_custom_uboot" <<- 'FETCH_CUSTOM_UBOOT'
			*allow extensions to fetch extra uboot sources*
			For downstream uboot et al.
			This is done after `GIT_SKIP_SUBMODULES="${UBOOT_GIT_SKIP_SUBMODULES}" fetch_from_repo "$BOOTSOURCE" "$BOOTDIR" "$BOOTBRANCH" "yes"`
		FETCH_CUSTOM_UBOOT
	fi

	# not optimal, but extra cleaning before overlayfs_wrapper should keep sources directory clean
	maybe_make_clean_uboot

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
	hash=$(git --git-dir="$ubootdir"/.git rev-parse HEAD)

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
	uboottempdir="$(mktemp -d)" # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	chmod 700 "${uboottempdir}"
	mkdir -p "$uboottempdir/$uboot_name/usr/lib/u-boot" "$uboottempdir/$uboot_name/usr/lib/$uboot_name" "$uboottempdir/$uboot_name/DEBIAN"

	# Allow extension-based u-boot bulding. We call the hook, and if EXTENSION_BUILT_UBOOT="yes" afterwards, we skip our own compilation.
	# This is to make it easy to build vendor/downstream uboot with their own quirks.

	display_alert "Extensions: build custom uboot" "build_custom_uboot" "debug"
	call_extension_method "build_custom_uboot" <<- 'BUILD_CUSTOM_UBOOT'
		*allow extensions to build their own uboot*
		For downstream uboot et al.
		Set \`EXTENSION_BUILT_UBOOT=yes\` to then skip the normal compilation.
	BUILD_CUSTOM_UBOOT

	if [[ "${EXTENSION_BUILT_UBOOT}" != "yes" ]]; then
		loop_over_uboot_targets_and_do compile_uboot_target
	else
		display_alert "Extensions: custom uboot built by extension" "not building regular uboot" "debug"
	fi

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

	run_host_command_logged rsync --remove-source-files -r "$uboottempdir/${uboot_name}.deb" "${DEB_STORAGE}/"

	display_alert "Built u-boot deb OK" "${uboot_name}.deb" "info"
	return 0 # success
}
