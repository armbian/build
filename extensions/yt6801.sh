# @description Installs the Motorcomm YT6801 Ethernet controller driver as a DKMS kernel module. Queries the GitHub API for the latest `amazingfate/yt6801-dkms` release, downloads its `.deb` into the chroot (via `ghproxy` when `GITHUB_MIRROR=ghproxy`) and installs it to build against the target kernel. Forces `INSTALL_HEADERS=yes`; needs a working headers package.

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
	declare api_output
	if ! api_output=$(curl -f --silent --show-error --location "${api_url}" 2>&1); then
		display_alert "Failed to fetch the latest release from GitHub" "${api_output}" "error"
		return 1
	fi
	latest_version=$(printf '%s' "${api_output}" | jq -r '.tag_name' 2> /dev/null || true)
	if [[ -z "${latest_version}" || "${latest_version}" == "null" ]]; then
		# 60 requests/hour per IP unauthenticated; a busy runner hits that, and an
		# unchecked null used to end up inside the download filename.
		display_alert "GitHub API returned no release tag (rate limited?)" "${api_url}" "error"
		return 1
	fi
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
