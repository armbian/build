#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# This add's amazingfate's PPAs to the the image, and installs all needed packages.
# It only works on LINUXFAMILY="rk3588-legacy" and RELEASE=jammy and BRANCH=legacy/vendor
# if on a desktop, installs more useful packages, and tries to coerce lightdm to use gtk-greeter and a Wayland session.
function extension_prepare_config__amazingfate_rk35xx_multimedia() {
	display_alert "Preparing amazingfate's PPAs for rk35xx multimedia" "${EXTENSION}" "info"
	EXTRA_IMAGE_SUFFIXES+=("-amazingfated") # Add to the image suffix. # global array

	[[ "${BUILDING_IMAGE}" != "yes" ]] && return 0

	if [[ "${RELEASE}" != "jammy" ]]; then
		display_alert "skipping..." "${EXTENSION} not for ${RELEASE}, only jammy, skipping" "warn"
		return 0
	fi

	if [[ "${LINUXFAMILY}" != "rockchip-rk3588" && "${LINUXFAMILY}" != "rk35xx" ]]; then
		exit_with_error "${EXTENSION} only works on LINUXFAMILY=rockchip-rk3588/rk35xx, currently on '${LINUXFAMILY}'"
	fi

	if [[ "${BRANCH}" != "legacy" && "${BRANCH}" != "vendor" && "${BRANCH}" != "vendor-boogie-panthor" ]]; then
		exit_with_error "${EXTENSION} only works on BRANCH=legacy/vendor/vendor-boogie-panthor, currently on '${BRANCH}'"
	fi
}

function post_install_kernel_debs__amazingfated_rk35xx_multimedia() {
	if [[ "${RELEASE}" != "jammy" ]]; then
		display_alert "skipping..." "${EXTENSION} not for ${RELEASE}, only jammy, skipping" "info"
		return 0
	fi

	display_alert "Adding rockchip-multimedia by Amazingfate PPAs" "${EXTENSION}" "info"

	do_with_retries 3 chroot_sdcard add-apt-repository ppa:liujianfeng1994/rockchip-multimedia --yes --no-update

	display_alert "Updating sources list, after rockchip-multimedia by Amazingfate PPAs" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get_update

	declare -a pkgs=(rockchip-multimedia-config)
	if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
		pkgs+=(chromium-browser libwidevinecdm)
		pkgs+=("libv4l-rkmpp" "gstreamer1.0-rockchip") # @TODO: remove when added as dependencies to chromium...?
	fi

	display_alert "Installing rockchip-multimedia by Amazingfate packages" "${EXTENSION} :: ${pkgs[*]}" "info"
	do_with_retries 3 chroot_sdcard_apt_get_install "${pkgs[@]}"

	display_alert "Upgrading rockchip-multimedia by Amazingfate packages" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get upgrade

	display_alert "Installed rockchip-multimedia by Amazingfate packages" "${EXTENSION}" "info"

	return 0
}
