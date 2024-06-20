#
# Extension to manage network interfaces with systemd-networkd + Netplan
#
function add_host_dependencies__install_systemd_networkd() {
        display_alert "Extension: ${EXTENSION}: Installing additional packages" "netplan.io" "info"
        add_packages_to_rootfs netplan.io
}

function pre_install_kernel_debs__configure_systemd_networkd()
{
	display_alert "Extension: ${EXTENSION}: Enabling systemd-networkd" "" "info"

	# Enable networkd and resolved
	# Very likely not needed to enable manually since these services are enabled by default
	chroot_sdcard systemctl enable systemd-networkd.service || display_alert "Failed to enable systemd-networkd.service" "" "wrn"
	chroot_sdcard systemctl enable systemd-resolved.service || display_alert "Failed to enable systemd-resolved.service" "" "wrn"

	# Copy network config files into the appropriate folders
	display_alert "Configuring" "systemd-networkd and Netplan" "info"
	local netplan_config_src_folder="${EXTENSION_DIR}/config-networkd/netplan/"
	local netplan_config_dst_folder="${SDCARD}/etc/netplan/"

	local networkd_config_src_folder="${EXTENSION_DIR}/config-networkd/systemd/network/"
	local networkd_config_dst_folder="${SDCARD}/etc/systemd/network/"

	run_host_command_logged cp "${netplan_config_src_folder}"* "${netplan_config_dst_folder}"
	run_host_command_logged cp "${networkd_config_src_folder}"* "${networkd_config_dst_folder}"

	# Change the file permissions according to https://netplan.readthedocs.io/en/stable/security/
	chmod 600 "${SDCARD}"/etc/netplan/*
}
