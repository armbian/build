function extension_finish_config__install_kernel_headers_for_aic8800_dkms() {

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping aic8800 dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with aic8800 dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__install_aic8800_dkms_package() {

	if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 7.2; then
		display_alert "Kernel version is too recent" "skipping aic8800 dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0
	[[ -z $AIC8800_TYPE ]] && return 0
	api_url="https://api.github.com/repos/radxa-pkg/aic8800/releases/latest"
	latest_version=$(curl -s "${api_url}" | jq -r '.tag_name')

	# Determine the DKMS package name based on the requested AIC8800_TYPE.
	declare aic8800_dkms_file_name
	case "${AIC8800_TYPE}" in
		"pcie") aic8800_dkms_file_name="aic8800-pcie-dkms_${latest_version}_all.deb" ;;
		"sdio") aic8800_dkms_file_name="aic8800-sdio-dkms_${latest_version}_all.deb" ;;
		"usb") aic8800_dkms_file_name="aic8800-usb-dkms_${latest_version}_all.deb" ;;
		*) return 0 ;;
	esac
	declare aic8800_firmware_file_name="aic8800-firmware_${latest_version}_all.deb"

	# Optional ghproxy mirror prefix for the download URLs.
	declare ghproxy_header=""
	if [[ "${GITHUB_MIRROR}" == "ghproxy" ]]; then
		ghproxy_header="https://ghfast.top/"
	fi
	declare base_url="https://github.com/radxa-pkg/aic8800/releases/download/${latest_version}"

	# Local download cache on the host; the version is part of the filename, so it doubles as the cache key.
	declare down_dir="${SRC}/cache/radxa-aic8800-debs"
	mkdir -p "${down_dir}"

	# Download (if not already cached) and stage each deb into the chroot's /tmp for installation.
	declare deb_file full_deb_path down_url
	for deb_file in "${aic8800_dkms_file_name}" "${aic8800_firmware_file_name}"; do
		full_deb_path="${down_dir}/${deb_file}"
		if [[ ! -f "${full_deb_path}" ]]; then
			down_url="${ghproxy_header}${base_url}/${deb_file}"
			display_alert "Will download ${full_deb_path} from latest release..." "${EXTENSION}" "info"
			wget --progress=dot:mega --local-encoding=UTF-8 --output-document="${full_deb_path}.tmp" "${down_url}"
			mv -v "${full_deb_path}.tmp" "${full_deb_path}"
		fi
		cp -v "${full_deb_path}" "${SDCARD}/tmp/${deb_file}"
	done

	display_alert "Install aic8800 packages, will build kernel module in chroot" "${EXTENSION}" "info"
	if [[ "${RELEASE}" == "noble" ]]; then
		display_alert "Installing gcc-14 for DKMS build" "${EXTENSION}" "info"
		use_clean_environment="yes" chroot_sdcard_apt_get_install "gcc-14"
		use_clean_environment="yes" chroot_sdcard "update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100"
	fi
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/aic8800*/*/build/*.log")
	use_clean_environment="yes" chroot_sdcard_apt_get_install "/tmp/${aic8800_dkms_file_name} /tmp/${aic8800_firmware_file_name}"
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
