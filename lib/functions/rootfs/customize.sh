#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function customize_image() {
	# for users that need to prepare files at host
	# shellcheck source=/dev/null
	[[ -f $USERPATCHES_PATH/customize-image-host.sh ]] && source "$USERPATCHES_PATH"/customize-image-host.sh

	call_extension_method "pre_customize_image" "image_tweaks_pre_customize" <<- 'PRE_CUSTOMIZE_IMAGE'
		*run before customize-image.sh*
		This hook is called after `customize-image-host.sh` is called, but before the overlay is mounted.
		It thus can be used for the same purposes as `customize-image-host.sh`.
		Attention: only the Distro default repos are enabled at this point; no packages from Armbian or custom repos can be used.
		If you need repos, please consider `post_armbian_repo_customize_image` or `post_repo_customize_image`.
	PRE_CUSTOMIZE_IMAGE

	cp "$USERPATCHES_PATH"/customize-image.sh "${SDCARD}"/tmp/customize-image.sh
	chmod +x "${SDCARD}"/tmp/customize-image.sh
	mkdir -p "${SDCARD}"/tmp/overlay

	# util-linux >= 2.27 required
	[[ -d "${USERPATCHES_PATH}"/overlay ]] && mount -o bind,ro "${USERPATCHES_PATH}"/overlay "${SDCARD}"/tmp/overlay
	display_alert "Calling image customization script" "customize-image.sh" "info"

	set +e # disable error control
	chroot_sdcard /tmp/customize-image.sh "${RELEASE}" "$LINUXFAMILY" "$BOARD" "$BUILD_DESKTOP" "$ARCH"
	CUSTOMIZE_IMAGE_RC=$?
	set -e # back to normal error control

	mountpoint -q "${SDCARD}"/tmp/overlay && umount "${SDCARD}"/tmp/overlay
	mountpoint -q "${SDCARD}"/tmp/overlay || rm -r "${SDCARD}"/tmp/overlay
	if [[ $CUSTOMIZE_IMAGE_RC != 0 ]]; then
		exit_with_error "customize-image.sh exited with error (rc: $CUSTOMIZE_IMAGE_RC)"
	fi

	call_extension_method "post_customize_image" "image_tweaks_post_customize" <<- 'POST_CUSTOMIZE_IMAGE'
		*post customize-image.sh hook*
		Run after the customize-image.sh script is run, and the overlay is unmounted.
		Attention: only the Distro default repos are enabled at this point; no Armbian or custom repos can be used.
	POST_CUSTOMIZE_IMAGE

	return 0
}

function post_repo_apt_update() {
	# update package lists after customizing the image
	display_alert "Updating APT package lists" "after customization" "info"
	do_with_retries 3 chroot_sdcard_apt_get_update
}

function run_hooks_post_armbian_repo_customize_image() {
	call_extension_method "post_armbian_repo_customize_image" <<- 'post_armbian_repo_customize_image'
		*run after post_customize_image, after and only if Armbian standard repos have been enabled*
		All repos have been enabled, including the Armbian repo and custom ones.
		You can install packages from the Armbian repo here.
	post_armbian_repo_customize_image
	return 0
}

function run_hooks_post_repo_customize_image() {
	call_extension_method "post_repo_customize_image" <<- 'post_repo_customize_image'
		*run after post_customize_image, after repos have been enabled*
		All repos have been enabled, including custom ones; Armbian repo is not guaranteed to be enabled.
		You can install packages from the default Debian/Ubuntu repos, or custom repos, here.
		To install packages from the Armbian repo, use the post_armbian_repo_customize_image hook.
	post_repo_customize_image
	return 0
}
