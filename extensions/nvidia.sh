#!/usr/bin/env bash
function extension_finish_config__build_nvidia_kernel_module() {
	# Deny on minimal CLI images
	if [[ "${BUILD_MINIMAL}" == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}" "skip installation in minimal images" "warn"
		return 0
	fi

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping nVidia for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g MODULES_BLACKLIST="nouveau"
	declare -g INSTALL_HEADERS="yes"
	# NVIDIA_DRIVER_VERSION is intentionally NOT defaulted here. The
	# post_install hook below asks apt (inside the chroot, after apt
	# sources are wired up) which nvidia-dkms-<N> is actually
	# available for the target distribution/release and picks the
	# highest one. Debian-style unversioned `nvidia-dkms` is the
	# fall-back when no numbered variants exist (Debian bookworm,
	# trixie). Set NVIDIA_DRIVER_VERSION via env or config to pin.
	display_alert "Forcing INSTALL_HEADERS=yes" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__build_nvidia_kernel_module() {
	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0

	# Resolve which nvidia-dkms / nvidia-driver package(s) to install.
	# Three cases:
	#   1. Operator pinned NVIDIA_DRIVER_VERSION (env/config) → trust it.
	#   2. Auto-detect: highest `nvidia-dkms-<N>` in the chroot's apt
	#      index. This is the common Ubuntu shape — 535, 550, 560,
	#      580, … depending on release and snapshot.
	#   3. Fall through to the unversioned Debian metapackage
	#      `nvidia-dkms` when no numeric variants exist.
	# If none of the three resolve, skip with a warning rather than
	# blowing the build up with an opaque "package not found".
	local nvidia_dkms_pkg nvidia_driver_pkg
	if [[ -n "${NVIDIA_DRIVER_VERSION:-}" ]]; then
		nvidia_dkms_pkg="nvidia-dkms-${NVIDIA_DRIVER_VERSION}"
		nvidia_driver_pkg="nvidia-driver-${NVIDIA_DRIVER_VERSION}"
		display_alert "Using pinned NVIDIA_DRIVER_VERSION" "${NVIDIA_DRIVER_VERSION}" "info"
	else
		local latest
		latest=$(chroot_sdcard "apt-cache pkgnames 'nvidia-dkms-' 2>/dev/null \
			| grep -E '^nvidia-dkms-[0-9]+\$' \
			| sed 's/nvidia-dkms-//' \
			| sort -nr | head -1")
		if [[ -n "$latest" ]]; then
			NVIDIA_DRIVER_VERSION="$latest"
			nvidia_dkms_pkg="nvidia-dkms-${NVIDIA_DRIVER_VERSION}"
			nvidia_driver_pkg="nvidia-driver-${NVIDIA_DRIVER_VERSION}"
			display_alert "Auto-detected nvidia-dkms for ${DISTRIBUTION}/${RELEASE}" "${NVIDIA_DRIVER_VERSION}" "info"
		elif chroot_sdcard "apt-cache pkgnames nvidia-dkms 2>/dev/null | grep -qx nvidia-dkms"; then
			nvidia_dkms_pkg="nvidia-dkms"
			nvidia_driver_pkg="nvidia-driver"
			display_alert "Using unversioned nvidia-dkms metapackage" "${DISTRIBUTION}/${RELEASE}" "info"
		else
			display_alert "No nvidia-dkms package in ${DISTRIBUTION}/${RELEASE} apt sources" "skipping nVidia install" "warn"
			return 0
		fi
	fi

	display_alert "Install nVidia packages, build kernel module in chroot" "${EXTENSION} (${nvidia_dkms_pkg})" "info"
	# chroot_sdcard_apt_get_install() is in lib/logging/runners.sh which handles "running" of stuff nicely.
	# chroot_sdcard_apt_get_install() -> chroot_sdcard_apt_get() -> chroot_sdcard() -> run_host_command_logged_raw()
	# it handles bash-specific quoting issues, apt proxies, logging, and errors.
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/nvidia/*/build/make.log")
	chroot_sdcard_apt_get_install "${nvidia_dkms_pkg}" "${nvidia_driver_pkg}"
}
