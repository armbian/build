#!/usr/bin/env bash
function extension_finish_config__build_nvidia_kernel_module() {
	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping nVidia for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	declare -g NVIDIA_DRIVER_VERSION="${NVIDIA_DRIVER_VERSION:-"510"}" # @TODO: this might vary per-release and Debian/Ubuntu
	display_alert "Forcing INSTALL_HEADERS=yes; using nVidia driver version ${NVIDIA_DRIVER_VERSION}" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__build_nvidia_kernel_module() {
	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0
	display_alert "Install nVidia packages, build kernel module in chroot" "${EXTENSION}" "info"
	# chroot_sdcard_apt_get_install() is in lib/logging/runners.sh which handles "running" of stuff nicely.
	# chroot_sdcard_apt_get_install() -> chroot_sdcard_apt_get() -> chroot_sdcard() -> run_host_command_logged_raw()
	# it handles bash-specific quoting issues, apt proxies, logging, and errors.
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/nvidia/*/build/make.log")
	chroot_sdcard_apt_get_install "nvidia-dkms-${NVIDIA_DRIVER_VERSION}" "nvidia-driver-${NVIDIA_DRIVER_VERSION}" nvidia-settings
}
