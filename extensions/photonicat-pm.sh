function extension_finish_config__install_kernel_headers_for_photonicat_pm_dkms() {

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping photonicat-pm dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with photonicat-pm dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__install_photonicat_pm_dkms_package() {

	if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.20; then
		display_alert "Kernel version is too recent" "skipping photonicat-pm dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0
	api_url="https://api.github.com/repos/HackingGate/photonicat-pm/releases/latest"
	latest_version=$(curl -s "${api_url}" | jq -r '.tag_name')
	# Get the Debian version from changelog
	changelog_url="https://raw.githubusercontent.com/HackingGate/photonicat-pm/refs/tags/${latest_version}/debian/changelog"
	debian_version=$(curl -s "${changelog_url}" | head -1 | grep -oP 'photonicat-pm \(\K[^)]+')
	photonicat_pm_url="https://github.com/HackingGate/photonicat-pm/releases/download/${latest_version}/photonicat-pm-dkms_${debian_version}_all.deb"
	if [[ "${GITHUB_MIRROR}" == "ghproxy" ]]; then
		ghproxy_header="https://ghfast.top/"
		photonicat_pm_url=${ghproxy_header}${photonicat_pm_url}
	fi
	photonicat_pm_dkms_file_name=photonicat-pm-dkms_${debian_version}_all.deb
	use_clean_environment="yes" chroot_sdcard "curl -fsSL -o /tmp/${photonicat_pm_dkms_file_name} '${photonicat_pm_url}'"
	display_alert "Install photonicat-pm packages, will build kernel module in chroot" "${EXTENSION}" "info"
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/photonicat-pm*/*/build/*.log")
	use_clean_environment="yes" chroot_sdcard_apt_get_install "/tmp/${photonicat_pm_dkms_file_name}"
	use_clean_environment="yes" chroot_sdcard "rm -f /tmp/photonicat-pm*.deb"
}
