#
# SPDX-License-Identifier: GPL-2.0
# Armbian build framework extension
#
# Enables 3D and multimedia, 4K VPU with Chromium, acceleration for Ubuntu. Debian only 3D
#

function post_install_kernel_debs__3d() {
	# Silently deny old releases which are not supported but are still in the system
	[[ "${RELEASE}" =~ ^(bookworm|bullseye|buster|focal|jammy)$ ]] && return 0

	# Deny on minimal CLI images
	if [[ "${BUILD_MINIMAL}" == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}" "skip installation in minimal images" "warn"
		return 0
	fi

	# some desktops doesn't support wayland
	[[ "${DESKTOP_ENVIRONMENT}" == "xfce" || "${DESKTOP_ENVIRONMENT}" == "i3-wm" ]] && return 0

	# Packages that are going to be installed, always, both for cli and desktop
	declare -a pkgs=("libgl1-mesa-dri")

	if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
		pkgs+=("libglx-mesa0") # Mesa OpenGL extension library for X11
		pkgs+=("mesa-utils") # Mesa utilities for OpenGL information and testing
		pkgs+=("mesa-utils-extra") # Additional Mesa demonstration programs
		pkgs+=("glmark2") # OpenGL 2.0/3.0 benchmark suite
		pkgs+=("glmark2-wayland") # Glmark2 Wayland backend for benchmarking
		pkgs+=("glmark2-es2-wayland") # Glmark2 OpenGL ES 2.0 Wayland backend
		pkgs+=("glmark2-es2") # Glmark2 OpenGL ES 2.0 benchmark support
		pkgs+=("glmark2-x11") # Glmark2 X11 backend for benchmarking
		pkgs+=("glmark2-es2-x11") # Glmark2 OpenGL ES 2.0 X11 backend
		pkgs+=("vulkan-tools") # Vulkan utilities for testing and debugging (vulkaninfo, etc.)
		pkgs+=("mesa-vulkan-drivers") # Vulkan drivers for Mesa GPUs (Panfrost, Lima, Radeon, Intel, etc.)
	fi

	if [[ "${BUILD_DESKTOP}" == "yes" ]]; then # if desktop, add amazingfated's multimedia PPAs and rockchip-multimedia-config utility, chromium, gstreamer, etc
		if [[ "${LINUXFAMILY}" =~ ^(rockchip-rk3588|rk35xx)$ && "${RELEASE}" =~ ^(noble)$ && "${BRANCH}" =~ ^(vendor)$ ]]; then
			pkgs+=("rockchip-multimedia-config" "libv4l-rkmpp" "gstreamer1.0-rockchip" "libwidevinecdm0")
			display_alert "Adding amazingfated's multimedia PPAs" "${EXTENSION}" "info"
			do_with_retries 3 chroot_sdcard add-apt-repository ppa:liujianfeng1994/rockchip-multimedia --yes --no-update
			display_alert "Pinning amazingfated's multimedia PPAs" "${EXTENSION}" "info"
			cat <<- EOF > "${SDCARD}"/etc/apt/preferences.d/amazingfated-rk3588-rockchip-multimedia-pin
				Package: *
				Pin: release o=LP-PPA-liujianfeng1994-rockchip-multimedia
				Pin-Priority: 1001
			EOF
		fi
	fi

	display_alert "Updating sources list, after adding all PPAs" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get_update

	# KDE neon downgrades base-files for some reason. This prevents tacking it
	do_with_retries 3 chroot_sdcard apt-mark hold base-files

	if [[ "${BUILD_DESKTOP}" == "yes" ]]; then # This library must be installed before rockchip-multimedia; only for desktops
		do_with_retries 3 chroot_sdcard_apt_get_install libv4l-0
	fi

	display_alert "Installing 3D extension packages" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get_install "${pkgs[@]}"

	# This library gets downgraded
	if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
		if [[ "${RELEASE}" =~ ^(oracular|noble)$ && "${ARCH}" == arm* ]]; then
			do_with_retries 3 chroot_sdcard apt-mark hold libdav1d7
		fi
	fi

	display_alert "Upgrading all packages, including hopefully all mesa packages" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get -o Dpkg::Options::="--force-confold" --allow-downgrades dist-upgrade

	# KDE neon downgrade hack undo
	do_with_retries 3 chroot_sdcard apt-mark unhold base-files

	if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
		if [[ "${RELEASE}" =~ ^(oracular|noble)$ && "${ARCH}" == arm* ]]; then
			do_with_retries 3 chroot_sdcard apt-mark unhold libdav1d7
		fi
	fi

	return 0
}

