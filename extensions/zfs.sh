function extension_prepare_config__build_zfs_kernel_module() {
	export INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with ZFS" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__build_zfs_kernel_module() {
	display_alert "Install ZFS packages, will build kernel module in chroot" "${EXTENSION}" "info"
	declare -agx if_error_find_files_sdcard=("/var/lib/dkms/zfs/*/build/*.log")
	# See https://github.com/zfsonlinux/pkg-zfs/issues/69 for a bug with leaking env vars.
	use_clean_environment="yes" chroot_sdcard_apt_get_install "zfs-dkms zfsutils-linux"
}
