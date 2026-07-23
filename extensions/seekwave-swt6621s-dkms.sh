# SPDX-License-Identifier: GPL-2.0
#
# SeekWave SWT6621S DKMS driver
#
# For SWT6621S_TYPE=SDIO, this extension downloads a pinned commit from:
#   retro98boy/seekwave-swt6621s.git
#
# For SWT6621S_TYPE=USB, it currently skips with an informational message.

# Branch: kickpi-k3b-sdio-uart, Commit date: Jul 16, 2026
readonly SEEKWAVE_SWT6621S_COMMIT="b1b15016119cb21965fc64dd374e42f46f011bb4"

function extension_finish_config__install_seekwave_swt6621s_dkms() {
	if [[ "${SWT6621S_TYPE}" == "USB" ]]; then
		display_alert "SWT6621S_TYPE=USB is not supported yet" "skipping seekwave-swt6621s dkms" "info"
		return 0
	fi

	if [[ "${SWT6621S_TYPE}" != "SDIO" ]]; then
		display_alert "Unknown SWT6621S_TYPE='${SWT6621S_TYPE}'" "skipping seekwave-swt6621s dkms" "warn"
		return 0
	fi

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping seekwave-swt6621s dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi

	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with seekwave-swt6621s dkms" "${EXTENSION}" "debug"

	local seekwave_cache_dir="${SRC}/cache/seekwave-swt6621s-dkms"
	local seekwave_tarball_url="${GITHUB_SOURCE}/retro98boy/seekwave-swt6621s/archive/${SEEKWAVE_SWT6621S_COMMIT}.tar.gz"

	display_alert "Downloading SeekWave SWT6621S SDIO source" "${seekwave_tarball_url}" "info"
	run_host_command_logged mkdir -p "${seekwave_cache_dir}"
	run_host_command_logged curl -fsSL --progress-bar "${seekwave_tarball_url}" -o "${seekwave_cache_dir}/source.tar.gz"
}

function post_install_kernel_debs__install_seekwave_swt6621s_dkms_package() {
	if [[ "${SWT6621S_TYPE}" == "USB" ]]; then
		return 0
	fi

	if [[ "${SWT6621S_TYPE}" != "SDIO" ]]; then
		return 0
	fi

	if [[ "${INSTALL_HEADERS}" != "yes" || "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		return 0
	fi

	display_alert "Installing SeekWave SWT6621S DKMS driver" "${EXTENSION}" "info"

	use_clean_environment="yes" chroot_sdcard_apt_get_install "dkms"

	local seekwave_cache_dir="${SRC}/cache/seekwave-swt6621s-dkms"
	cp "${seekwave_cache_dir}/source.tar.gz" "${SDCARD}/tmp/seekwave-swt6621s.tar.gz"

	use_clean_environment="yes" chroot_sdcard "mkdir -p /usr/src/seekwave-swt6621s-1.0.0"
	use_clean_environment="yes" chroot_sdcard "tar -xzf /tmp/seekwave-swt6621s.tar.gz -C /tmp/"
	use_clean_environment="yes" chroot_sdcard "cp -a /tmp/seekwave-swt6621s-${SEEKWAVE_SWT6621S_COMMIT}/. /usr/src/seekwave-swt6621s-1.0.0/"
	use_clean_environment="yes" chroot_sdcard "rm -rf /tmp/seekwave-swt6621s.tar.gz /tmp/seekwave-swt6621s-${SEEKWAVE_SWT6621S_COMMIT}"

	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/seekwave-swt6621s*/*/build/*.log")
	display_alert "Building SeekWave SWT6621S kernel modules via DKMS" "${EXTENSION}" "info"

	if [[ -z "${IMAGE_INSTALLED_KERNEL_VERSION}" ]]; then
		display_alert "Cannot determine target kernel version" "SeekWave SWT6621S DKMS build skipped" "warn"
		return 0
	fi
	local target_kver="${IMAGE_INSTALLED_KERNEL_VERSION}-${BRANCH}-${LINUXFAMILY}"
	display_alert "Target kernel version for DKMS" "${target_kver}" "debug"

	use_clean_environment="yes" chroot_sdcard "dkms add -m seekwave-swt6621s -v 1.0.0"
	use_clean_environment="yes" chroot_sdcard "dkms build -m seekwave-swt6621s -v 1.0.0 -k ${target_kver}"
	use_clean_environment="yes" chroot_sdcard "dkms install -m seekwave-swt6621s -v 1.0.0 -k ${target_kver}"

	cat > "${SDCARD}/etc/modules-load.d/swt6621s-sdio-uart.conf" <<- 'EOF'
		skw_sdio_lite
		swt6621s_wifi
		skwbt
	EOF

	cat > "${SDCARD}/etc/modprobe.d/swt6621s-sdio-uart.conf" <<- 'EOF'
		options skw_sdio_lite firmware_dir=seekwave
		options swt6621s_wifi firmware_dir=seekwave
		options skwbt firmware_dir=seekwave
		softdep swt6621s_wifi pre: skw_sdio_lite
		softdep skwbt pre: swt6621s_wifi
	EOF

	display_alert "SeekWave SWT6621S DKMS driver installed" "${EXTENSION}" "info"
}
