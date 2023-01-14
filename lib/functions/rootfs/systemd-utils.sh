function disable_systemd_service_sdcard() {
	display_alert "Disabling systemd service(s) on target" "${*}" "debug"
	declare service
	for service in "${@}"; do
		chroot_sdcard systemctl --no-reload disable "${service}" "||" true
	done
}
