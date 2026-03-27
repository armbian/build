function extension_finish_config__install_kernel_headers_for_aic8800_dkms() {

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping aic8800 dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with aic8800 dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__install_aic8800_dkms_package() {
	if [[ "${INSTALL_HEADERS}" != "yes" || "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		return 0
	fi

	local api_url="https://api.github.com/repos/Shadowrom2020/aic8800-dkms/releases/latest"
	local latest_version
	local aic8800_dkms_url

	local api_output
	if ! api_output=$(curl -f --silent --show-error --location "${api_url}" 2>&1); then
		display_alert "Failed to fetch latest aic8800-dkms release from GitHub: ${api_output}" "${EXTENSION}" "error"
		return 1
	fi

	latest_version=$(printf '%s' "${api_output}" | jq -r '.tag_name' 2>/dev/null || true)
	if [[ -z "${latest_version}" || "${latest_version}" == "null" ]]; then
		display_alert "Invalid latest_version from GitHub API: '${latest_version}'" "${EXTENSION}" "error"
		return 1
	fi

	aic8800_dkms_url="https://github.com/Shadowrom2020/aic8800-dkms/releases/download/${latest_version}/aic8800-dkms.deb"
	if [[ "${GITHUB_MIRROR}" == "ghproxy" ]]; then
		local ghproxy_header="https://ghfast.top/"
		aic8800_dkms_url="${aic8800_dkms_url/https:\/\/github.com\//${ghproxy_header}github.com/}"
	fi

	use_clean_environment="yes" chroot_sdcard "wget \"${aic8800_dkms_url}\" -P /tmp"
	display_alert "Installing aic8800 package, will build kernel module in chroot" "${EXTENSION}" "info"
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/aic8800*/*/build/*.log")
	# eject is needed by the aic8800-dkms package/DKMS workflow to safely unmount
	# or eject media devices when building/installing kernel modules inside chroot.
	use_clean_environment="yes" chroot_sdcard_apt_get_install "eject"
	use_clean_environment="yes" chroot_sdcard_apt_get_install "/tmp/aic8800-dkms.deb"
	use_clean_environment="yes" chroot_sdcard "rm -f /tmp/aic8800-dkms.deb"
}
