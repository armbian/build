#
# Extension to manage network time synchronization with Chrony
#
function extension_prepare_config__install_chrony() {
	display_alert "Extension: ${EXTENSION}: Adding extra package to image" "chrony" "info"
	add_packages_to_image chrony
}
