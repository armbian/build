# @description Adds the `chrony` package to the image for network time synchronization. Chrony is a full-featured NTP client/server that syncs faster and copes with intermittent connections and jitter better than `systemd-timesyncd`. Enable it as the alternative time-sync extension when accurate or robust NTP is required.

#
# Extension to manage network time synchronization with Chrony
#
function extension_prepare_config__install_chrony() {
	display_alert "Extension: ${EXTENSION}: Adding extra package to image" "chrony" "info"
	add_packages_to_image chrony
}
