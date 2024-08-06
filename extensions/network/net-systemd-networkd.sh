#
# Extension to manage network interfaces with systemd-networkd + Netplan
#
function extension_prepare_config__install_systemd_networkd() {
	# Sanity check
	if [[ "${NETWORKING_STACK}" != "systemd-networkd" ]]; then
		exit_with_error "Extension: ${EXTENSION}: requires NETWORKING_STACK='systemd-networkd', currently set to '${NETWORKING_STACK}'"
	fi

	display_alert "Extension: ${EXTENSION}: Adding extra packages to image" "netplan.io" "info"
	add_packages_to_image netplan.io
}

function pre_install_kernel_debs__configure_systemd_networkd() {
	display_alert "Extension: ${EXTENSION}: Enabling systemd-networkd" "" "info"

	# Enable networkd and resolved
	# Very likely not needed to enable manually since these services are enabled by default
	chroot_sdcard systemctl enable systemd-networkd.service || display_alert "Failed to enable systemd-networkd.service" "" "wrn"
	chroot_sdcard systemctl enable systemd-resolved.service || display_alert "Failed to enable systemd-resolved.service" "" "wrn"

	# Copy network config files into the appropriate folders
	display_alert "Extension: ${EXTENSION}: Configuring" "systemd-networkd and Netplan" "info"
	local netplan_config_src_folder="${EXTENSION_DIR}/config-networkd/netplan/"
	local netplan_config_dst_folder="${SDCARD}/etc/netplan/"

	local networkd_config_src_folder="${EXTENSION_DIR}/config-networkd/systemd/network/"
	local networkd_config_dst_folder="${SDCARD}/etc/systemd/network/"

	run_host_command_logged cp -v "${netplan_config_src_folder}"* "${netplan_config_dst_folder}"
	run_host_command_logged cp -v "${networkd_config_src_folder}"* "${networkd_config_dst_folder}"

	# Change the file permissions according to https://netplan.readthedocs.io/en/stable/security/
	chmod -v 600 "${SDCARD}"/etc/netplan/*
}
