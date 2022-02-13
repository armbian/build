compile_atf() {
	if [[ $CLEAN_LEVEL == *make* ]]; then
		display_alert "Cleaning" "$ATFSOURCEDIR" "info"
		(
			cd "${SRC}/cache/sources/${ATFSOURCEDIR}"
			make distclean 2>&1
		)
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

	# ENABLE_BACKTRACE="0" has been added to workaround a regression in ATF.
	# Check: https://github.com/armbian/build/issues/1157
	CCACHE_BASEDIR="$(pwd)" PATH="${toolchain}:${toolchain2}:${PATH}" \
		make ENABLE_BACKTRACE="0" $target_make $CTHREADS \
		CROSS_COMPILE="$CCACHE $ATF_COMPILER" 2>&1 || { # HANDLED SHORTCIRCUIT: direct command invocation; @TODO: replace with runner
		exit_with_error "ATF compilation failed"
	}

	[[ $(type -t atf_custom_postprocess) == function ]] && atf_custom_postprocess 2>&1

	atftempdir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	chmod 700 ${atftempdir}

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

	return 0 # avoid error due to short-circuit above
}
