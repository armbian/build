#
# Extension for Network Manager + Netplan + Chrony
#
function add_host_dependencies__install_network_manager() {
	display_alert "Adding Networking manager related packages" "network-manager network-manager-openvpn" "info"
	add_packages_to_rootfs network-manager network-manager-openvpn netplan.io chrony
	if [[ "${BUILD_DESKTOP}" == "yes" ]]; then
	add_packages_to_rootfs network-manager-gnome network-manager-ssh network-manager-vpnc
	fi
	if [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then
	add_packages_to_rootfs network-manager-config-connectivity-ubuntu
	fi
}

function pre_install_kernel_debs__configure_network_manager()
{
	display_alert "${EXTENSION}: enabling Network Manager" "" "info"

	# configure network manager
	sed "s/managed=\(.*\)/managed=true/g" -i "${SDCARD}"/etc/NetworkManager/NetworkManager.conf

	## remove network manager defaults to handle eth by default @TODO: why?
	# rm -f "${SDCARD}"/usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf

	# `systemd-networkd.service` will be enabled by `/lib/systemd/system-preset/90-systemd.preset` during first-run.
	# Mask it to avoid conflict
	chroot_sdcard systemctl mask systemd-networkd.service

	# most likely we don't need to wait for nm to get online
	chroot_sdcard systemctl disable NetworkManager-wait-online.service

	if [[ -n $NM_IGNORE_DEVICES ]]; then
		mkdir -p "${SDCARD}"/etc/NetworkManager/conf.d/
		cat <<- EOF > "${SDCARD}"/etc/NetworkManager/conf.d/10-ignore-interfaces.conf
			[keyfile]
			unmanaged-devices=$NM_IGNORE_DEVICES
		EOF
	fi

	# Let NetworkManager manage all devices on this system by default
	cat <<- EOF > "${SDCARD}"/etc/netplan/armbian-default.yaml
	# This installation supports NetworkManager renderer only. You need to install additional packages in case you want something else
	network:
	  version: 2
	  renderer: NetworkManager
	EOF

}
