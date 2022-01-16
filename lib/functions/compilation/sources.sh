function fetch_sources_kernel_uboot_atf() {
	if [[ -n $BOOTSOURCE ]]; then
		display_alert "Downloading sources" "u-boot" "git"
		fetch_from_repo "$BOOTSOURCE" "$BOOTDIR" "$BOOTBRANCH" "yes" # fetch_from_repo <url> <dir> <ref> <subdir_flag>
	fi

	if [[ -n $KERNELSOURCE ]]; then
		display_alert "Downloading sources" "kernel" "git"
		fetch_from_repo "$KERNELSOURCE" "$KERNELDIR" "$KERNELBRANCH" "yes"
	fi

	if [[ -n $ATFSOURCE ]]; then
		display_alert "Downloading sources" "atf" "git"
		fetch_from_repo "$ATFSOURCE" "$ATFDIR" "$ATFBRANCH" "yes"
	fi
}
