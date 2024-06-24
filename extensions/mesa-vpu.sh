#
# SPDX-License-Identifier: GPL-2.0
# Armbian build framework extension
#
# Enables 3D and multimedia, 4K VPU with Chromium, acceleration for Ubuntu. Debian only 3D
#

function extension_prepare_config__3d() {

	# only used when generating image
	[[ "${BUILDING_IMAGE}" != "yes" ]] && return 0

	# only used when generating desktop
	[[ "${BUILD_DESKTOP}" != "yes" ]] && return 0

	# Define image suffix
	if [[ "${LINUXFAMILY}" =~ ^(rockchip-rk3588|rk35xx)$ && "$BRANCH" =~ ^(legacy)$ && "${RELEASE}" =~ ^(jammy|noble)$ ]]; then

		EXTRA_IMAGE_SUFFIXES+=("-panfork")

	elif [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then

		EXTRA_IMAGE_SUFFIXES+=("-oibaf")

	fi

	# This should be enabled on all for rk3588 distributions where mesa and vendor kernel is present
	if [[ "${LINUXFAMILY}" =~ ^(rockchip-rk3588|rk35xx)$ && "$BRANCH" == vendor ]]; then
		declare -g DEFAULT_OVERLAYS="panthor-gpu"
	fi

}

function post_install_kernel_debs__3d() {

	# Silently deny old releases which are not supported but are still in the system
	[[ "${RELEASE}" =~ ^(bullseye|buster|focal)$ ]] && return 0

	# Do not install those packages on CLI and minimal images
	[[ "${BUILD_DESKTOP}" != "yes" ]] && return 0

	# Packages that are going to be installed
	declare -a pkgs=("mesa-utils" "mesa-utils-extra" "libglx-mesa0" "libgl1-mesa-dri" "glmark2" "glmark2-wayland" "glmark2-es2-wayland" "glmark2-es2")

	# Some packages, x11gl benchmark, came late into Ubuntu
	[[ "${RELEASE}" != jammy ]] && pkgs+=("glmark2-x11" "glmark2-es2-x11")

	# Rockchip RK3588 will use panfork only with legacy kernel
	if [[ "${LINUXFAMILY}" =~ ^(rockchip-rk3588|rk35xx)$ && "$BRANCH" =~ ^(legacy)$ && "${RELEASE}" =~ ^(jammy|noble)$ ]]; then

		display_alert "Adding amazingfated's rk3588 PPAs" "${EXTENSION}" "info"
		do_with_retries 3 chroot_sdcard add-apt-repository ppa:liujianfeng1994/panfork-mesa --yes --no-update

		display_alert "Pinning amazingfated's rk3588 PPAs" "${EXTENSION}" "info"
		cat <<- EOF > "${SDCARD}"/etc/apt/preferences.d/amazingfated-rk3588-panfork-pin
			Package: *
			Pin: release o=LP-PPA-liujianfeng1994-panfork-mesa
			Pin-Priority: 1001
		EOF

		sed -i "s/noble/jammy/g" "${SDCARD}"/etc/apt/sources.list.d/liujianfeng1994-ubuntu-panfork-mesa-"${RELEASE}".*

	elif [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then

		display_alert "Adding oibaf PPAs" "${EXTENSION}" "info"
		do_with_retries 3 chroot_sdcard add-apt-repository ppa:oibaf/graphics-drivers --yes --no-update

		display_alert "Pinning oibaf PPAs" "${EXTENSION}" "info"
		cat <<- EOF > "${SDCARD}"/etc/apt/preferences.d/mesa-oibaf-graphics-drivers-pin
			Package: *
			Pin: release o=LP-PPA-oibaf-graphics-drivers
			Pin-Priority: 1001
		EOF

	fi

	if [[ "${LINUXFAMILY}" =~ ^(rockchip-rk3588|rk35xx)$ && "${RELEASE}" =~ ^(jammy|noble)$ && "${BRANCH}" =~ ^(legacy|vendor)$ ]]; then

		pkgs+=("rockchip-multimedia-config" "chromium-browser" "libv4l-rkmpp" "gstreamer1.0-rockchip")
		if [[ "${RELEASE}" == "jammy" ]]; then
			pkgs+=(libwidevinecdm)
		else
			pkgs+=(libwidevinecdm0)
		fi

		display_alert "Adding amazingfated's multimedia PPAs" "${EXTENSION}" "info"
		do_with_retries 3 chroot_sdcard add-apt-repository ppa:liujianfeng1994/rockchip-multimedia --yes --no-update

		display_alert "Pinning amazingfated's multimedia PPAs" "${EXTENSION}" "info"
		cat <<- EOF > "${SDCARD}"/etc/apt/preferences.d/amazingfated-rk3588-rockchip-multimedia-pin
			Package: *
			Pin: release o=LP-PPA-liujianfeng1994-rockchip-multimedia
			Pin-Priority: 1001
		EOF
	fi

	display_alert "Updating sources list, after oibaf PPAs" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get_update

	display_alert "Installing 3D extension packages" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get_install --allow-downgrades "${pkgs[@]}"

	display_alert "Upgrading Mesa packages" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get dist-upgrade

}
