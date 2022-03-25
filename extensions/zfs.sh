function pre_install_kernel_debs__build_zfs_kernel_module() {

	export INSTALL_HEADERS="yes"

}

function post_install_kernel_debs__build_zfs_kernel_module() {

	display_alert "Build kernel module" "${EXTENSION}" "info"
	chroot "${SDCARD}" /bin/bash -c "apt -y -qq install zfs-dkms zfsutils-linux" >>"$DEST"/"${LOG_SUBPATH}"/install.log 2>&1 || {
		exit_with_error "${install_grub_cmdline} failed!"
	}
}
