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

	# some desktops doesn't support wayland
	[[ "${DESKTOP_ENVIRONMENT}" == "xfce" || "${DESKTOP_ENVIRONMENT}" == "i3-wm" ]] && return 0

	# Define image suffix
	if [[ "${LINUXFAMILY}" =~ ^(rockchip-rk3588|rk35xx)$ && "$BRANCH" =~ ^(legacy)$ && "${RELEASE}" =~ ^(jammy|noble)$ ]]; then

		EXTRA_IMAGE_SUFFIXES+=("-panfork")

	elif [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then

		EXTRA_IMAGE_SUFFIXES+=("-kisak")

	elif [[ "${DISTRIBUTION}" == "Debian" && "${RELEASE}" == "bookworm" ]]; then

		EXTRA_IMAGE_SUFFIXES+=("-backported-mesa")

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

	# some desktops doesn't support wayland
	[[ "${DESKTOP_ENVIRONMENT}" == "xfce" || "${DESKTOP_ENVIRONMENT}" == "i3-wm" ]] && return 0

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

		display_alert "Adding kisak PPAs" "${EXTENSION}" "info"
		do_with_retries 3 chroot_sdcard add-apt-repository ppa:kisak/kisak-mesa --yes --no-update

		display_alert "Pinning kisak PPAs" "${EXTENSION}" "info"
		cat <<- EOF > "${SDCARD}"/etc/apt/preferences.d/mesa-kisak-kisak-mesa-pin
			Package: *
			Pin: release o=LP-PPA-kisak-kisak-mesa
			Pin-Priority: 1001
		EOF

		if [[ "${ARCH}" == "arm64" ]]; then

			display_alert "Adding Amazingfate Chromium PPAs" "${EXTENSION}" "info"
			do_with_retries 3 chroot_sdcard add-apt-repository ppa:liujianfeng1994/chromium --yes --no-update
			sed -i "s/oracular/noble/g" "${SDCARD}"/etc/apt/sources.list.d/liujianfeng1994-ubuntu-chromium-"${RELEASE}".*

			display_alert "Pinning amazingfated's Chromium PPAs" "${EXTENSION}" "info"
			cat <<- EOF > "${SDCARD}"/etc/apt/preferences.d/liujianfeng1994-chromium-pin
			Package: chromium
			Pin: release o=LP-PPA-liujianfeng1994-chromium
			Pin-Priority: 1001
			EOF

		else

			display_alert "Adding Xtradebs Apps PPAs" "${EXTENSION}" "info"
			do_with_retries 3 chroot_sdcard add-apt-repository ppa:xtradeb/apps --yes --no-update
			sed -i "s/oracular/noble/g" "${SDCARD}"/etc/apt/sources.list.d/xtradeb-ubuntu-apps-"${RELEASE}".*

	                display_alert "Pinning Xtradebs PPAs" "${EXTENSION}" "info"
        	        cat <<- EOF > "${SDCARD}"/etc/apt/preferences.d/xtradebs-apps-pin
			Package: chromium
			Pin: release o=LP-PPA-xtradebs-apps
			Pin-Priority: 1001
			EOF

		fi

		pkgs+=("chromium")

	elif [[ "${DISTRIBUTION}" == "Debian" && "${RELEASE}" == "bookworm" ]]; then

		display_alert "Adding mesa backport repo for ${RELEASE} from OBS" "${EXTENSION}" "info"
		echo 'deb http://download.opensuse.org/repositories/home:/amazingfate:/mesa-bookworm-backport/Debian_12/ /' | tee "${SDCARD}"/etc/apt/sources.list.d/home:amazingfate:mesa-bookworm-backport.list
		curl -fsSL https://download.opensuse.org/repositories/home:amazingfate:mesa-bookworm-backport/Debian_12/Release.key | gpg --dearmor | tee "${SDCARD}"/etc/apt/trusted.gpg.d/home_amazingfate_mesa-bookworm-backport.gpg > /dev/null

	fi

	if [[ "${LINUXFAMILY}" =~ ^(rockchip-rk3588|rk35xx)$ && "${RELEASE}" =~ ^(jammy|noble)$ && "${BRANCH}" =~ ^(legacy|vendor)$ ]]; then

		pkgs+=("rockchip-multimedia-config" "chromium" "libv4l-rkmpp" "gstreamer1.0-rockchip")
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

	display_alert "Updating sources list, after kisak PPAs" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get_update

	display_alert "Installing 3D extension packages" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get_install --allow-downgrades "${pkgs[@]}"

	display_alert "Upgrading Mesa packages" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get dist-upgrade

	# Disable wayland flag for XFCE
	#if [[ "${DESKTOP_ENVIRONMENT}" == "xfce" ]]; then
	#	sed -e '/wayland/ s/^#*/#/' -i "${SDCARD}"/etc/chromium.d/default-flags
	#fi

}
