# @description Installs the Broadcom `bcmdhd` WiFi driver as a DKMS module. Downloads the latest `pcie`, `sdio`, or `usb` variant `.deb` (selected by `BCMDHD_TYPE`) from the `armbian/bcmdhd-dkms` GitHub releases and builds it in the chroot. Forces `INSTALL_HEADERS=yes`; skips when `BCMDHD_TYPE` is unset or the kernel lacks working headers.

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
	bcmdhd_pcie_url="https://github.com/armbian/bcmdhd-dkms/releases/download/${latest_version}/bcmdhd-pcie-dkms_${latest_version}_all.deb"
	bcmdhd_sdio_url="https://github.com/armbian/bcmdhd-dkms/releases/download/${latest_version}/bcmdhd-sdio-dkms_${latest_version}_all.deb"
	bcmdhd_usb_url="https://github.com/armbian/bcmdhd-dkms/releases/download/${latest_version}/bcmdhd-usb-dkms_${latest_version}_all.deb"
	if [[ "${GITHUB_MIRROR}" == "ghproxy" ]]; then
		ghproxy_header="https://ghfast.top/"
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
