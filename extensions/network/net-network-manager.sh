#
# Extension to manage network interfaces with NetworkManager + Netplan
#
function add_host_dependencies__install_network_manager() {
	display_alert "Extension: ${EXTENSION}: Installing additional packages" "network-manager network-manager-openvpn netplan.io" "info"
	add_packages_to_rootfs network-manager network-manager-openvpn netplan.io

	if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}: Installing additional packages for desktop" "network-manager-gnome network-manager-ssh network-manager-vpnc" "info"
		add_packages_to_rootfs network-manager-gnome network-manager-ssh network-manager-vpnc
	fi

	if [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then
		display_alert "Extension: ${EXTENSION}: Installing additional packages for Ubuntu" "network-manager-config-connectivity-ubuntu" "info"
		add_packages_to_rootfs network-manager-config-connectivity-ubuntu
	fi
}

function pre_install_kernel_debs__configure_network_manager() {
	display_alert "Extension: ${EXTENSION}: Enabling Network-Manager" "" "info"

	# We can't disable/mask systemd-networkd.service since it is required by Netplan

	# Most likely we don't need to wait for nm to get online
	chroot_sdcard systemctl disable NetworkManager-wait-online.service

	# Copy network config files into the appropriate folders
	display_alert "Configuring" "NetworkManager and Netplan" "info"
	local netplan_config_src_folder="${EXTENSION_DIR}/config-nm/netplan/"
	local netplan_config_dst_folder="${SDCARD}/etc/netplan/"

	local network_manager_config_src_folder="${EXTENSION_DIR}/config-nm/NetworkManager/"
	local network_manager_config_dst_folder="${SDCARD}/etc/NetworkManager/conf.d/"

	run_host_command_logged cp "${netplan_config_src_folder}"* "${netplan_config_dst_folder}"
	run_host_command_logged cp "${network_manager_config_src_folder}"* "${network_manager_config_dst_folder}"

	# Change the file permissions according to https://netplan.readthedocs.io/en/stable/security/
	chmod 600 "${SDCARD}"/etc/netplan/*
}
