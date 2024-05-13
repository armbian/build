#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2024 Ricardo Pardini <ricardo@pardini.net>
# Copyright (c) 2024 Monka
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/

# This add's oibaf PPAs to the the image, and installs all needed packages.
# It only works with mainline mesa enabled kernels, eg, not legacy/vendor ones, usually.

function extension_prepare_config__oibaf() {
	display_alert "Preparing oibaf extension" "${EXTENSION}" "info"

	if [[ "${DISTRIBUTION}" != "Ubuntu" ]]; then
		display_alert "oibaf" "${EXTENSION} extension only works with Ubuntu (currently '${DISTRIBUTION}'), skipping" "warn"
		return 0
	fi

	[[ "${BUILD_DESKTOP}" != "yes" ]] && return 0

	# Add to the image suffix.
	EXTRA_IMAGE_SUFFIXES+=("-oibaf") # global array
}

function post_install_kernel_debs__oibaf() {

	if [[ "${DISTRIBUTION}" != "Ubuntu" ]]; then
		display_alert "oibaf" "${EXTENSION} extension only works with Ubuntu, skipping" "debug"
		return 0
	fi

	[[ "${BUILD_DESKTOP}" != "yes" ]] && return 0

	display_alert "Adding oibaf PPAs" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard add-apt-repository ppa:oibaf/graphics-drivers --yes --no-update

	display_alert "Pinning oibaf PPAs" "${EXTENSION}" "info"
	cat <<- EOF > "${SDCARD}"/etc/apt/preferences.d/mesa-oibaf-graphics-drivers-pin
	Package: *
	Pin: release o=LP-PPA-oibaf-graphics-drivers
	Pin-Priority: 1001
	EOF

	# Ubuntu oracular workaround
	local url_to_check="https://ppa.launchpadcontent.net/oibaf/graphics-drivers/ubuntu/dists/${RELEASE}/Release"
	if curl -o/dev/null -sfIL "$url_to_check" 2>&1; then
		:
	else
		display_alert "Converting to generic sources list due to missing release file" "${EXTENSION}" "info"
		sed -i "s/${RELEASE}/noble/g" "${SDCARD}"/etc/apt/sources.list.d/oibaf-ubuntu-graphics-drivers-"${RELEASE}".sources
	fi

	display_alert "Updating sources list, after oibaf PPAs" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get_update

	display_alert "Installing oibaf packages" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get_install glmark2-wayland glmark2-es2 glmark2-es2-wayland mesa-utils

	display_alert "Upgrading oibaf packages" "${EXTENSION}" "info"
	do_with_retries 3 chroot_sdcard_apt_get dist-upgrade

	display_alert "Installed oibaf packages" "${EXTENSION}" "info"
}
