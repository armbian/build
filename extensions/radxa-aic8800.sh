# @description Installs the AIC8800 WiFi DKMS driver and firmware for Radxa boards. Downloads the `aic8800-<type>-dkms` and firmware debs (`pcie`/`sdio`/`usb` per `AIC8800_TYPE`) from the latest `radxa-pkg/aic8800` release, or the one set in `AIC8800_VERSION`, and builds the module in the chroot. Forces `INSTALL_HEADERS=yes` and needs working kernel headers. With `AIC8800_SDIO_BT=yes` it also installs the UART Bluetooth service, and `AIC8800_MODPROBE_OPTIONS` goes to /etc/modprobe.d/aic8800.conf.

function extension_finish_config__install_kernel_headers_for_aic8800_dkms() {

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping aic8800 dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with aic8800 dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__install_aic8800_dkms_package() {

	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0
	[[ -z $AIC8800_TYPE ]] && return 0
	declare latest_version="${AIC8800_VERSION:-}"
	if [[ -z "${latest_version}" ]]; then
		latest_version="$(github_latest_release_tag "radxa-pkg/aic8800")" || return 1
	fi

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

function post_family_tweaks_bsp__aic8800_config() {
	if [[ -n "${AIC8800_MODPROBE_OPTIONS}" ]]; then
		run_host_command_logged mkdir -p "${destination}/etc/modprobe.d"
		echo "${AIC8800_MODPROBE_OPTIONS}" > "${destination}/etc/modprobe.d/aic8800.conf"
	fi

	[[ "${AIC8800_TYPE}" == "sdio" && "${AIC8800_SDIO_BT}" == "yes" ]] || return 0
	display_alert "Installing AIC8800 UART Bluetooth service" "${EXTENSION}" "info"
	run_host_command_logged mkdir -p "${destination}/etc/modules-load.d"
	printf '%s\n' hidp rfcomm bnep aic8800_btlpm_sdio > "${destination}/etc/modules-load.d/aic8800-btlpm.conf"
	run_host_command_logged install -D -m 0755 "${SRC}/packages/bsp/aic8800/aic-bluetooth" "${destination}/usr/bin/aic-bluetooth"
	run_host_command_logged install -D -m 0644 "${SRC}/packages/bsp/aic8800/aic-bluetooth.service" "${destination}/usr/lib/systemd/system/aic-bluetooth.service"
}

function post_family_tweaks__aic8800_enable_bluetooth_service() {
	[[ "${AIC8800_TYPE}" == "sdio" && "${AIC8800_SDIO_BT}" == "yes" ]] || return 0
	if chroot_sdcard test -f /usr/lib/systemd/system/aic-bluetooth.service; then
		chroot_sdcard systemctl --no-reload enable aic-bluetooth.service
	else
		display_alert "aic-bluetooth.service not found in image" "${EXTENSION}" "warn"
	fi
}
