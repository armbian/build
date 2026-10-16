# @description Installs the Seekwave SWT6621S WiFi/BT DKMS driver and firmware. Downloads the `swt6621s-dkms` and `swt6621s-firmware` debs from the latest `Novice-PG/swt6621s` release and builds the modules in the chroot. Forces `INSTALL_HEADERS=yes` — requires a kernel with a working headers package.

function extension_finish_config__install_kernel_headers_for_swt6621s_dkms() {

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping swt6621s dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with swt6621s dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__install_swt6621s_dkms_packages() {

	if [[ "${INSTALL_HEADERS}" != "yes" || "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		return 0
	fi

	local latest_version
	latest_version="$(github_latest_release_tag "Novice-PG/swt6621s")" || return 1

	local -a swt6621s_deb_files=(
		"swt6621s-dkms_${latest_version}_all.deb"
		"swt6621s-firmware_${latest_version}_all.deb"
	)

	# Use the configured ghproxy when GitHub is mirrored, like the rest of the build.
	local release_prefix="https://github.com"
	if [[ "${GITHUB_MIRROR}" == "ghproxy" ]]; then
		release_prefix="https://${GHPROXY_ADDRESS:-ghfast.top}/https://github.com"
	fi
	local base_url="${release_prefix}/Novice-PG/swt6621s/releases/download/${latest_version}"

	# Local download cache on the host; the version is part of the filename, so it doubles as the cache key.
	local down_dir="${SRC}/cache/swt6621s-debs"
	mkdir -p "${down_dir}"

	# Download (if not already cached) and stage each deb into the chroot's /tmp for installation.
	local deb_file full_deb_path
	for deb_file in "${swt6621s_deb_files[@]}"; do
		full_deb_path="${down_dir}/${deb_file}"
		if [[ ! -f "${full_deb_path}" ]]; then
			display_alert "Will download ${full_deb_path} from latest release..." "${EXTENSION}" "info"
			wget --progress=dot:mega --local-encoding=UTF-8 --output-document="${full_deb_path}.tmp" "${base_url}/${deb_file}"
			mv -v "${full_deb_path}.tmp" "${full_deb_path}"
		fi
		cp -v "${full_deb_path}" "${SDCARD}/tmp/${deb_file}"
	done

	display_alert "Install swt6621s packages, will build kernel modules in chroot" "${EXTENSION}" "info"
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/swt6621s*/*/build/*.log")
	use_clean_environment="yes" chroot_sdcard_apt_get_install "/tmp/${swt6621s_deb_files[0]} /tmp/${swt6621s_deb_files[1]}"
	use_clean_environment="yes" chroot_sdcard "rm -f /tmp/swt6621s*.deb"
}
