function fetch_sources_kernel_uboot_atf() {
	if [[ -n $KERNELSOURCE ]]; then
		display_alert "Downloading sources" "kernel" "git"
		GIT_COLD_BUNDLE_URL="${MAINLINE_KERNEL_COLD_BUNDLE_URL}" \
			fetch_from_repo "$KERNELSOURCE" "$KERNELDIR" "$KERNELBRANCH" "yes"
	fi

	if [[ -n $BOOTSOURCE ]] && [[ "${BOOTSOURCE}" != "none" ]]; then
		display_alert "Downloading sources" "u-boot" "git"
		fetch_from_repo "$BOOTSOURCE" "$BOOTDIR" "$BOOTBRANCH" "yes" # fetch_from_repo <url> <dir> <ref> <subdir_flag>
	fi

	if [[ -n "${ATFSOURCE}" && "${ATFSOURCE}" != "none" ]]; then
		display_alert "Downloading sources" "atf" "git"
		fetch_from_repo "$ATFSOURCE" "$ATFDIR" "$ATFBRANCH" "yes"
	fi
}
