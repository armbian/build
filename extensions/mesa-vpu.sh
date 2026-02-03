#
# SPDX-License-Identifier: GPL-2.0
# Armbian build framework extension
#
# Enables 3D and multimedia, 4K VPU with Chromium, acceleration for Ubuntu. Debian only 3D
#

function extension_prepare_config__3d() {
	# Silently deny old releases which are not supported but are still in the system
	[[ "${RELEASE}" =~ ^(bookworm|bullseye|buster|focal|jammy)$ ]] && return 0

	# Deny on minimal CLI images
	if [[ "${BUILD_MINIMAL}" == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}" "skip installation in minimal images" "warn"
		return 0
	fi

	# some desktops doesn't support wayland
	[[ "${DESKTOP_ENVIRONMENT}" == "xfce" || "${DESKTOP_ENVIRONMENT}" == "i3-wm" ]] && return 0

	# This should be enabled on all for rk3588 distributions where mesa and vendor kernel is present
	if [[ "${LINUXFAMILY}" =~ ^(rockchip-rk3588|rk35xx)$ && "$BRANCH" == vendor ]]; then
		if [[ -n $DEFAULT_OVERLAYS ]]; then
			DEFAULT_OVERLAYS+=" panthor-gpu"
		else
			declare -g DEFAULT_OVERLAYS="panthor-gpu"
		fi
	fi

}

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
		pkgs+=("libglx-mesa0") # x11 stuff all the way
		pkgs+=("mesa-utils" "mesa-utils-extra")
		pkgs+=("glmark2" "glmark2-wayland" "glmark2-es2-wayland" "glmark2-es2" "glmark2-x11" "glmark2-es2-x11")
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

function post_armbian_repo_customize_image__browser() {
	# Silently deny old releases which are not supported but are still in the system
	[[ "${RELEASE}" =~ ^(bookworm|bullseye|buster|focal|jammy)$ ]] && return 0

	# Add browser if building a desktop - architecture dependent
	[[ "${BUILD_DESKTOP}" != "yes" ]] && return 0

	if [[ "${ARCH}" == "amd64" ]]; then
		# amd64: prefer google-chrome
		pkgs=("google-chrome-stable")
	elif [[ "${ARCH}" =~ ^(arm64|armhf)$ ]]; then
		# arm64/armhf: use chromium
		pkgs=("chromium")
	else
		# other architectures: fallback to firefox
		pkgs=("firefox")
	fi

	display_alert "Installing browser" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get_install "${pkgs[@]}"

	return 0
}
