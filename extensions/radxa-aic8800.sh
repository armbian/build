function extension_finish_config__install_kernel_headers_for_aic8800_dkms() {

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping aic8800 dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with aic8800 dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__install_aic8800_dkms_package() {

	if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 6.18; then
		display_alert "Kernel version is too recent" "skipping aic8800 dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0
	[[ -z $AIC8800_TYPE ]] && return 0
	api_url="https://api.github.com/repos/radxa-pkg/aic8800/releases/latest"
	latest_version=$(curl -s "${api_url}" | jq -r '.tag_name')
	aic8800_firmware_url="https://github.com/radxa-pkg/aic8800/releases/download/${latest_version}/aic8800-firmware_${latest_version}_all.deb"
	aic8800_pcie_url="https://github.com/radxa-pkg/aic8800/releases/download/${latest_version}/aic8800-pcie-dkms_${latest_version}_all.deb"
	aic8800_sdio_url="https://github.com/radxa-pkg/aic8800/releases/download/${latest_version}/aic8800-sdio-dkms_${latest_version}_all.deb"
	aic8800_usb_url="https://github.com/radxa-pkg/aic8800/releases/download/${latest_version}/aic8800-usb-dkms_${latest_version}_all.deb"
	if [[ "${GITHUB_MIRROR}" == "ghproxy" ]]; then
		ghproxy_header="https://ghfast.top/"
		aic8800_firmware_url=${ghproxy_header}${aic8800_firmware_url}
		aic8800_pcie_url=${ghproxy_header}${aic8800_pcie_url}
		aic8800_sdio_url=${ghproxy_header}${aic8800_sdio_url}
		aic8800_usb_url=${ghproxy_header}${aic8800_usb_url}
	fi
	case "${AIC8800_TYPE}" in
		"pcie")
			aic8800_dkms_file_name=aic8800-pcie-dkms_${latest_version}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${aic8800_pcie_url} -P /tmp"
			;;
		"sdio")
			aic8800_dkms_file_name=aic8800-sdio-dkms_${latest_version}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${aic8800_sdio_url} -P /tmp"
			;;
		"usb")
			aic8800_dkms_file_name=aic8800-usb-dkms_${latest_version}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${aic8800_usb_url} -P /tmp"
			;;
		*)
			return 0
			;;
	esac
	use_clean_environment="yes" chroot_sdcard "wget ${aic8800_firmware_url} -P /tmp"
	display_alert "Install aic8800 packages, will build kernel module in chroot" "${EXTENSION}" "info"
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/aic8800*/*/build/*.log")
	use_clean_environment="yes" chroot_sdcard_apt_get_install "/tmp/${aic8800_dkms_file_name} /tmp/aic8800-firmware_${latest_version}_all.deb"
	use_clean_environment="yes" chroot_sdcard "rm -f /tmp/aic8800*.deb"
	use_clean_environment="yes" chroot_sdcard "mkdir -p /usr/lib/systemd/network/"
	use_clean_environment="yes" chroot_sdcard 'cat <<- EOF > /usr/lib/systemd/network/50-radxa-aic8800.link
		[Match]
		OriginalName=wlan*
		Driver=usb

		[Link]
		NamePolicy=kernel
	EOF'
}
