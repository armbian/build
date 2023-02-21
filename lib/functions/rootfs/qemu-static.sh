function deploy_qemu_binary_to_chroot() {
	local chroot_target="${1}"

	# @TODO: rpardini: Only deploy the binary if we're actually building a different architecture? otherwise unneeded.

	if [[ ! -f "${chroot_target}/usr/bin/${QEMU_BINARY}" ]]; then
		display_alert "Deploying qemu-user-static binary to chroot" "${QEMU_BINARY}" "debug"
		run_host_command_logged cp -pv "/usr/bin/${QEMU_BINARY}" "${chroot_target}/usr/bin/"
	else
		display_alert "qemu-user-static binary already deployed, skipping" "${QEMU_BINARY}" "debug"
	fi
}

function undeploy_qemu_binary_from_chroot() {
	local chroot_target="${1}"

	# Hack: Check for magic "/usr/bin/qemu-s390x-static" marker; if that exists, it means "qemu-user-static" was installed
	# in the chroot, and we shouldn't remove the binary, otherwise it's gonna be missing in the final image.
	if [[ -f "${chroot_target}/usr/bin/qemu-s390x-static" ]]; then
		display_alert "Not removing qemu binary, qemu-user-static package is installed in the chroot" "${QEMU_BINARY}" "debug"
		return 0
	fi

	if [[ -f "${chroot_target}/usr/bin/${QEMU_BINARY}" ]]; then
		display_alert "Removing qemu-user-static binary from chroot" "${QEMU_BINARY}" "debug"
		run_host_command_logged rm -fv "${chroot_target}/usr/bin/${QEMU_BINARY}"
	fi
}
