# for boards with watchdog support - add watchdog package and
# enable hardware watchdog device (/dev/watchdog) support in config

function extension_prepare_config__add_to_image_watchdog() {
	display_alert "Extension: ${EXTENSION}: Adding extra package to image" "watchdog" "info"
	add_packages_to_image watchdog
}

function post_customize_image__enable_watchdog_device_config() {
	display_alert "Enable /dev/watchdog in /etc/watchdog.conf ${HOOK_POINT}" "${EXTENSION}" "info"
	sed -e 'sX^#watchdog-deviceXwatchdog-deviceX' -i  "${SDCARD}"/etc/watchdog.conf
}
