#
# Extension to manage network time synchronization with Chrony
#
function add_host_dependencies__install_chrony() {
        display_alert "Extension: ${EXTENSION}: Installing additional packages" "chrony" "info"
        add_packages_to_rootfs chrony
}
