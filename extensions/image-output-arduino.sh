function post_build_image__900_convert_to_arduino_img() {
	[[ -z $version ]] && exit_with_error "version is not set"
	
	display_alert "Converting image $version" "${EXTENSION}" "info"
	declare -g BOOTFS_IMAGE_FILE="${DESTIMG}/${version}.bootfs.img"
	bootfs_start_sector=$(gdisk -l ${DESTIMG}/${version}.img | grep bootfs | awk '{print $2}')
	bootfs_end_sector=$(gdisk -l ${DESTIMG}/${version}.img | grep bootfs | awk '{print $3}')

	declare -g ROOTFS_IMAGE_FILE="${DESTIMG}/${version}.rootfs.img"
	rootfs_start_sector=$(gdisk -l ${DESTIMG}/${version}.img | grep rootfs | awk '{print $2}')
	rootfs_end_sector=$(gdisk -l ${DESTIMG}/${version}.img | grep rootfs | awk '{print $3}')
	
	old_image_loop_device=$(losetup -f -P --show ${DESTIMG}/${version}.img)
	
	dd if=${old_image_loop_device}p1 of=${BOOTFS_IMAGE_FILE}
	dd if=${old_image_loop_device}p2 of=${ROOTFS_IMAGE_FILE}
	
	rm -rf arduino-images
	mkdir -p arduino-images
	cp -r ${SRC}/packages/blobs/arduino/flash arduino-images
	
	mkdir rootfs_mount
	mount ${ROOTFS_IMAGE_FILE} rootfs_mount
	cp rootfs_mount/usr/lib/linux-u-boot-edge-arduino-uno-q/boot.img arduino-images/flash
	umount rootfs_mount

	losetup -d ${old_image_loop_device}
	
	rm ${DESTIMG}/${version}.img
	
	mv ${BOOTFS_IMAGE_FILE} arduino-images/disk-sdcard.img.esp
	mv ${ROOTFS_IMAGE_FILE} arduino-images/disk-sdcard.img.root
	
	tar -Jcvf ${DESTIMG}/${version}.tar.xz arduino-images
	rm -rf arduino-images

	return 0
}
