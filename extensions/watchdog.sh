# @description Installs the `watchdog` daemon package and configures it for hardware watchdog support. Uncomments `watchdog-device` in `/etc/watchdog.conf` so the daemon uses `/dev/watchdog` to reset a hung system. Enable it for boards with a hardware watchdog that should trigger automatic recovery on lockups.

# for boards with watchdog support - add watchdog package and
# enable hardware watchdog device (/dev/watchdog) support in config

function extension_prepare_config__add_to_image_watchdog() {
	display_alert "Extension: ${EXTENSION}: Adding extra package to image" "watchdog" "info"
	add_packages_to_image watchdog
}

function post_customize_image__enable_watchdog_device_config() {
	display_alert "Enable /dev/watchdog in /etc/watchdog.conf ${HOOK_POINT}" "${EXTENSION}" "info"
	sed -e 'sX^#watchdog-deviceXwatchdog-deviceX' -i "${SDCARD}"/etc/watchdog.conf
}
