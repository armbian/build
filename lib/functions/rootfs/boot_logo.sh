function boot_logo() {
	display_alert "Building kernel splash logo" "$RELEASE" "info"

	LOGO=${SRC}/packages/blobs/splash/logo.png
	LOGO_WIDTH=$(identify $LOGO | cut -d " " -f 3 | cut -d x -f 1)
	LOGO_HEIGHT=$(identify $LOGO | cut -d " " -f 3 | cut -d x -f 2)
	THROBBER=${SRC}/packages/blobs/splash/spinner.gif
	THROBBER_WIDTH=$(identify $THROBBER | head -1 | cut -d " " -f 3 | cut -d x -f 1)
	THROBBER_HEIGHT=$(identify $THROBBER | head -1 | cut -d " " -f 3 | cut -d x -f 2)
	convert -alpha remove -background "#000000" $LOGO "${SDCARD}"/tmp/logo.rgb
	convert -alpha remove -background "#000000" $THROBBER "${SDCARD}"/tmp/throbber%02d.rgb

	run_host_x86_binary_logged "${SRC}/packages/blobs/splash/bootsplash-packer" \
		--bg_red 0x00 \
		--bg_green 0x00 \
		--bg_blue 0x00 \
		--frame_ms 48 \
		--picture \
		--pic_width $LOGO_WIDTH \
		--pic_height $LOGO_HEIGHT \
		--pic_position 0 \
		--blob "${SDCARD}"/tmp/logo.rgb \
		--picture \
		--pic_width $THROBBER_WIDTH \
		--pic_height $THROBBER_HEIGHT \
		--pic_position 0x05 \
		--pic_position_offset 200 \
		--pic_anim_type 1 \
		--pic_anim_loop 0 \
		--blob "${SDCARD}"/tmp/throbber00.rgb \
		--blob "${SDCARD}"/tmp/throbber01.rgb \
		--blob "${SDCARD}"/tmp/throbber02.rgb \
		--blob "${SDCARD}"/tmp/throbber03.rgb \
		--blob "${SDCARD}"/tmp/throbber04.rgb \
		--blob "${SDCARD}"/tmp/throbber05.rgb \
		--blob "${SDCARD}"/tmp/throbber06.rgb \
		--blob "${SDCARD}"/tmp/throbber07.rgb \
		--blob "${SDCARD}"/tmp/throbber08.rgb \
		--blob "${SDCARD}"/tmp/throbber09.rgb \
		--blob "${SDCARD}"/tmp/throbber10.rgb \
		--blob "${SDCARD}"/tmp/throbber11.rgb \
		--blob "${SDCARD}"/tmp/throbber12.rgb \
		--blob "${SDCARD}"/tmp/throbber13.rgb \
		--blob "${SDCARD}"/tmp/throbber14.rgb \
		--blob "${SDCARD}"/tmp/throbber15.rgb \
		--blob "${SDCARD}"/tmp/throbber16.rgb \
		--blob "${SDCARD}"/tmp/throbber17.rgb \
		--blob "${SDCARD}"/tmp/throbber18.rgb \
		--blob "${SDCARD}"/tmp/throbber19.rgb \
		--blob "${SDCARD}"/tmp/throbber20.rgb \
		--blob "${SDCARD}"/tmp/throbber21.rgb \
		--blob "${SDCARD}"/tmp/throbber22.rgb \
		--blob "${SDCARD}"/tmp/throbber23.rgb \
		--blob "${SDCARD}"/tmp/throbber24.rgb \
		--blob "${SDCARD}"/tmp/throbber25.rgb \
		--blob "${SDCARD}"/tmp/throbber26.rgb \
		--blob "${SDCARD}"/tmp/throbber27.rgb \
		--blob "${SDCARD}"/tmp/throbber28.rgb \
		--blob "${SDCARD}"/tmp/throbber29.rgb \
		--blob "${SDCARD}"/tmp/throbber30.rgb \
		--blob "${SDCARD}"/tmp/throbber31.rgb \
		--blob "${SDCARD}"/tmp/throbber32.rgb \
		--blob "${SDCARD}"/tmp/throbber33.rgb \
		--blob "${SDCARD}"/tmp/throbber34.rgb \
		--blob "${SDCARD}"/tmp/throbber35.rgb \
		--blob "${SDCARD}"/tmp/throbber36.rgb \
		--blob "${SDCARD}"/tmp/throbber37.rgb \
		--blob "${SDCARD}"/tmp/throbber38.rgb \
		--blob "${SDCARD}"/tmp/throbber39.rgb \
		--blob "${SDCARD}"/tmp/throbber40.rgb \
		--blob "${SDCARD}"/tmp/throbber41.rgb \
		--blob "${SDCARD}"/tmp/throbber42.rgb \
		--blob "${SDCARD}"/tmp/throbber43.rgb \
		--blob "${SDCARD}"/tmp/throbber44.rgb \
		--blob "${SDCARD}"/tmp/throbber45.rgb \
		--blob "${SDCARD}"/tmp/throbber46.rgb \
		--blob "${SDCARD}"/tmp/throbber47.rgb \
		--blob "${SDCARD}"/tmp/throbber48.rgb \
		--blob "${SDCARD}"/tmp/throbber49.rgb \
		--blob "${SDCARD}"/tmp/throbber50.rgb \
		--blob "${SDCARD}"/tmp/throbber51.rgb \
		--blob "${SDCARD}"/tmp/throbber52.rgb \
		--blob "${SDCARD}"/tmp/throbber53.rgb \
		--blob "${SDCARD}"/tmp/throbber54.rgb \
		--blob "${SDCARD}"/tmp/throbber55.rgb \
		--blob "${SDCARD}"/tmp/throbber56.rgb \
		--blob "${SDCARD}"/tmp/throbber57.rgb \
		--blob "${SDCARD}"/tmp/throbber58.rgb \
		--blob "${SDCARD}"/tmp/throbber59.rgb \
		--blob "${SDCARD}"/tmp/throbber60.rgb \
		--blob "${SDCARD}"/tmp/throbber61.rgb \
		--blob "${SDCARD}"/tmp/throbber62.rgb \
		--blob "${SDCARD}"/tmp/throbber63.rgb \
		--blob "${SDCARD}"/tmp/throbber64.rgb \
		--blob "${SDCARD}"/tmp/throbber65.rgb \
		--blob "${SDCARD}"/tmp/throbber66.rgb \
		--blob "${SDCARD}"/tmp/throbber67.rgb \
		--blob "${SDCARD}"/tmp/throbber68.rgb \
		--blob "${SDCARD}"/tmp/throbber69.rgb \
		--blob "${SDCARD}"/tmp/throbber70.rgb \
		--blob "${SDCARD}"/tmp/throbber71.rgb \
		--blob "${SDCARD}"/tmp/throbber72.rgb \
		--blob "${SDCARD}"/tmp/throbber73.rgb \
		--blob "${SDCARD}"/tmp/throbber74.rgb \
		"${SDCARD}"/lib/firmware/bootsplash.armbian

	if [[ $BOOT_LOGO == yes || $BOOT_LOGO == desktop && $BUILD_DESKTOP == yes ]]; then
		[[ -f "${SDCARD}"/boot/armbianEnv.txt ]] && grep -q '^bootlogo' "${SDCARD}"/boot/armbianEnv.txt &&
			sed -i 's/^bootlogo.*/bootlogo=true/' "${SDCARD}"/boot/armbianEnv.txt || echo 'bootlogo=true' >> "${SDCARD}"/boot/armbianEnv.txt
		[[ -f "${SDCARD}"/boot/boot.ini ]] && sed -i 's/^setenv bootlogo.*/setenv bootlogo "true"/' "${SDCARD}"/boot/boot.ini
	fi
	# enable additional services
	chroot_sdcard systemctl --no-reload enable bootsplash-ask-password-console.path || true
	chroot_sdcard systemctl --no-reload enable bootsplash-hide-when-booted.service || true
	chroot_sdcard systemctl --no-reload enable bootsplash-show-on-shutdown.service || true
	return 0
}
