# update_initramfs
#
# this should be invoked as late as possible for any modifications by
# customize_image (userpatches) and prepare_partitions to be reflected in the
# final initramfs
#
# especially, this needs to be invoked after /etc/crypttab has been created
# for cryptroot-unlock to work:
# https://serverfault.com/questions/907254/cryproot-unlock-with-dropbear-timeout-while-waiting-for-askpass
#
# since Debian buster, it has to be called within create_image() on the $MOUNT
# path instead of $SDCARD (which can be a tmpfs and breaks cryptsetup-initramfs).
# see: https://github.com/armbian/build/issues/1584
update_initramfs() {
	local chroot_target=$1
	local target_dir="$(find "${chroot_target}/lib/modules"/ -maxdepth 1 -type d -name "*${VER}*")"
	if [ "$target_dir" != "" ]; then
		update_initramfs_cmd="update-initramfs -uv -k $(basename "$target_dir")"
	else
		exit_with_error "No kernel installed for the version" "${VER}"
	fi
	display_alert "Updating initramfs..." "$update_initramfs_cmd" ""
	cp "/usr/bin/$QEMU_BINARY" "$chroot_target/usr/bin"/
	mount_chroot "$chroot_target/"

	chroot_custom_long_running "$chroot_target" "$update_initramfs_cmd" || {
		exit_with_error "Updating initramfs FAILED"
	}
	display_alert "Updated initramfs." "${update_initramfs_cmd}" "info"

	display_alert "Re-enabling" "initramfs-tools hook for kernel"
	chroot "$chroot_target" /bin/bash -c "chmod -v +x /etc/kernel/postinst.d/initramfs-tools" 2>&1

	umount_chroot "$chroot_target/"
	rm $chroot_target/usr/bin/$QEMU_BINARY

}
