function extension_finish_config__install_kernel_headers_for_bcmdhd_dkms() {

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping bcmdhd dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with bcmdhd dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__install_bcmdhd_dkms_package() {

	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0
	[[ -z $BCMDHD_TYPE ]] && return 0
	api_url="https://api.github.com/repos/armbian/bcmdhd-dkms/releases/latest"
	latest_version=$(curl -s "${api_url}" | jq -r '.tag_name')
	bcmdhd_pcie_url="https://github.com/armbian/bcmdhd-dkms/releases/download/${latest_version}/bcmdhd-pcie-dkms_${latest_version}_all.deb"
	bcmdhd_sdio_url="https://github.com/armbian/bcmdhd-dkms/releases/download/${latest_version}/bcmdhd-sdio-dkms_${latest_version}_all.deb"
	bcmdhd_usb_url="https://github.com/armbian/bcmdhd-dkms/releases/download/${latest_version}/bcmdhd-usb-dkms_${latest_version}_all.deb"
	if [[ "${GITHUB_MIRROR}" == "ghproxy" ]]; then
		ghproxy_header="https://mirror.ghproxy.com/"
		bcmdhd_pcie_url=${ghproxy_header}${bcmdhd_pcie_url}
		bcmdhd_sdio_url=${ghproxy_header}${bcmdhd_sdio_url}
		bcmdhd_usb_url=${ghproxy_header}${bcmdhd_usb_url}
	fi
	case "${BCMDHD_TYPE}" in
		"pcie")
			bcmdhd_dkms_file_name=bcmdhd-pcie-dkms_${latest_version}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${bcmdhd_pcie_url} -P /tmp"
			;;
		"sdio")
			bcmdhd_dkms_file_name=bcmdhd-sdio-dkms_${latest_version}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${bcmdhd_sdio_url} -P /tmp"
			;;
		"usb")
			bcmdhd_dkms_file_name=bcmdhd-usb-dkms_${latest_version}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${bcmdhd_usb_url} -P /tmp"
			;;
		*)
			return 0
			;;
	esac
	display_alert "Install bcmdhd packages, will build kernel module in chroot" "${EXTENSION}" "info"
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/bcmdhd*/*/build/*.log")
	use_clean_environment="yes" chroot_sdcard_apt_get_install /tmp/${bcmdhd_dkms_file_name}
	use_clean_environment="yes" chroot_sdcard "rm -f /tmp/bcmdhd*.deb"
}
