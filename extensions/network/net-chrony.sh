#
# Extension to manage network time synchronization with Chrony
#
function extension_prepare_config__install_chrony() {
	display_alert "Extension: ${EXTENSION}: Installing additional packages" "chrony" "info"
	add_packages_to_image chrony
}
