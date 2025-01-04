function extension_finish_config__build_v4l2loopback_dkms_kernel_module() {
	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping v4l2loopback-dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with v4l2loopback-dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__build_v4l2loopback_dkms_kernel_module() {
	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0
	display_alert "Install v4l2loopback-dkms packages, will build kernel module in chroot" "${EXTENSION}" "info"
	declare -g if_error_detail_message="v4l2loopback-dkms build failed, extension 'v4l2loopback-dkms'"
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/v4l2loopback*/*/build/*.log")
	use_clean_environment="yes" chroot_sdcard_apt_get_install "v4l2loopback-dkms v4l2loopback-utils v4l-utils"
}
