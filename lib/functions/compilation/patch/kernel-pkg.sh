function apply_kernel_patches_for_packaging() {
	local kerneldir="${1}"
	local version="${2}"
	# Packaging patch for modern kernels should be one for all.
	# Currently we have it per kernel family since we can't have one
	# Maintaining one from central location starting with 5.3+
	# Temporally set for new "default->legacy,next->current" family naming

	if linux-version compare "${version}" ge 5.10; then
		display_alert "NOT using old packaging mkdebian etc" "skipping mkdebian patching" "warn"
		return 0 # Not anymore for new packaging.

		# This case is special: it does not use process_patch_file. fasthash manually.
		local builddeb="packages/armbian/builddeb"
		local mkdebian="packages/armbian/mkdebian"
		local kernel_package_dir="${kerneldir}/scripts/package"
		if report_fashtash_should_execute text "$(cat "${SRC}/${builddeb}" "${SRC}/${mkdebian}")" "armbian builddeb and mkdebian replace"; then
			# Read mtime, then sed, then restore it
			local arm64_makefile="${kerneldir}/arch/arm64/Makefile" arm64_makefile_mtime
			arm64_makefile_mtime="$(get_file_modification_time "${arm64_makefile}")"
			# shellcheck disable=SC2016 # this should be a .patch?
			sed -i -e 's/^KBUILD_IMAGE	:= \$(boot)\/Image\.gz$/KBUILD_IMAGE	:= \$(boot)\/Image/' "${arm64_makefile}"
			set_files_modification_time "${arm64_makefile_mtime}" "${arm64_makefile}"

			# cp with -p to preserve the original dates
			cp -pv "${SRC}/${builddeb}" "${kernel_package_dir}/builddeb"
			cp -pv "${SRC}/${mkdebian}" "${kernel_package_dir}/mkdebian"

			chmod 755 "${kernel_package_dir}/builddeb" "${kernel_package_dir}/mkdebian"
			mark_fasthash_done # will do git commit, associate fasthash to real hash.
		fi

	elif linux-version compare "${version}" ge 5.8.17 &&
		linux-version compare "${version}" le 5.9 ||
		linux-version compare "${version}" ge 5.9.2; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-5.8-9.y.patch" "applying"
	elif linux-version compare "${version}" ge 5.6; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-5.6.y.patch" "applying"
	elif linux-version compare "${version}" ge 5.3; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-5.3.y.patch" "applying"
	fi

	if [[ "${version}" == "4.19."* ]] && [[ "$LINUXFAMILY" == sunxi* || "$LINUXFAMILY" == meson64 ||
		"$LINUXFAMILY" == mvebu64 || "$LINUXFAMILY" == mt7623 || "$LINUXFAMILY" == mvebu ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.19.y.patch" "applying"
	fi

	if [[ "${version}" == "4.19."* ]] && [[ "$LINUXFAMILY" == rk35xx ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.19.y-rk35xx.patch" "applying"
	fi

	if [[ "${version}" == "4.14."* ]] && [[ "$LINUXFAMILY" == s5p6818 || "$LINUXFAMILY" == mvebu64 ||
		"$LINUXFAMILY" == imx7d || "$LINUXFAMILY" == odroidxu4 || "$LINUXFAMILY" == mvebu ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.14.y.patch" "applying"
	fi

	if [[ "${version}" == "4.4."* || "${version}" == "4.9."* ]] &&
		[[ "$LINUXFAMILY" == rockpis || "$LINUXFAMILY" == rk3399 ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.4.y-rk3399.patch" "applying"
	fi

	if [[ "${version}" == "4.4."* ]] &&
		[[ "$LINUXFAMILY" == rockchip64 || "$LINUXFAMILY" == station* ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.4.y-rockchip64.patch" "applying"
	fi

	if [[ "${version}" == "4.4."* ]] && [[ "$LINUXFAMILY" == rockchip || "$LINUXFAMILY" == rk322x ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.4.y.patch" "applying"
	fi

	if [[ "${version}" == "4.9."* ]] && [[ "$LINUXFAMILY" == meson64 || "$LINUXFAMILY" == odroidc4 ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.9.y.patch" "applying"
	fi

}
