#
# Extension for ifupdown2
#
function add_host_dependencies__install_ifupdown2() {
        display_alert "Adding Netplan to systemd-networkd" "systemd-timesyncd" "info"
        add_packages_to_rootfs ifupdown2 iproute2 bridge-utils vlan
}

function pre_install_kernel_debs__configure_systemd_networkd()
{
	display_alert "${EXTENSION}: enabling ifupdown2" "" "info"

}
