function error_if_kernel_only_set() {
	if [[ "x${KERNEL_ONLY}x" != "xx" ]]; then
		display_alert "KERNEL_ONLY is not supported; use new" "./compile.sh kernel BOARD=${BOARD} BRANCH=${BRANCH} kernel" "err"
		exit_with_error "KERNEL_ONLY is set.This is not supported anymore. Please remove it, and use the new CLI commands."
		return 1
	fi
}

function error_if_lib_tag_set() {
	if [[ "x${LIB_TAG}x" != "xx" ]]; then
		exit_with_error "LIB_TAG is set.This is not supported anymore. Please remove it, and manage the git branches manually."
		return 1
	fi
}
