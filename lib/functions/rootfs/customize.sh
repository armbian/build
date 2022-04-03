customize_image() {

	# for users that need to prepare files at host
	[[ -f $USERPATCHES_PATH/customize-image-host.sh ]] && source "$USERPATCHES_PATH"/customize-image-host.sh

	call_extension_method "pre_customize_image" "image_tweaks_pre_customize" <<- 'PRE_CUSTOMIZE_IMAGE'
		*run before customize-image.sh*
		This hook is called after `customize-image-host.sh` is called, but before the overlay is mounted.
		It thus can be used for the same purposes as `customize-image-host.sh`.
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
	POST_CUSTOMIZE_IMAGE

	return 0
}
