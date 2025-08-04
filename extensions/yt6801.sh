function extension_finish_config__install_kernel_headers_for_yt6801_dkms() {

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping yt6801 dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with yt6801 dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__install_yt6801_dkms_package() {

	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0
	api_url="https://api.github.com/repos/amazingfate/yt6801-dkms/releases/latest"
	latest_version=$(curl -s "${api_url}" | jq -r '.tag_name')
	yt6801_dkms_url="https://github.com/amazingfate/yt6801-dkms/releases/download/${latest_version}/yt6801-dkms_${latest_version}_all.deb"
	if [[ "${GITHUB_MIRROR}" == "ghproxy" ]]; then
		ghproxy_header="https://ghfast.top/"
		yt6801_dkms_url=${ghproxy_header}${yt6801_dkms_url}
	fi
	yt6801_dkms_file_name=yt6801-dkms_${latest_version}_all.deb
	use_clean_environment="yes" chroot_sdcard "wget ${yt6801_dkms_url} -P /tmp"
	display_alert "Install yt6801 packages, will build kernel module in chroot" "${EXTENSION}" "info"
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/yt6801*/*/build/*.log")
	use_clean_environment="yes" chroot_sdcard_apt_get_install /tmp/${yt6801_dkms_file_name}
	use_clean_environment="yes" chroot_sdcard "rm -f /tmp/yt6801*.deb"
}
