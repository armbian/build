function post_build_image__900_convert_to_arduino_img() {
	[[ -z $version ]] && exit_with_error "version is not set"

	display_alert "Converting image $version" "${EXTENSION}" "info"
	declare -g BOOTFS_IMAGE_FILE="${DESTIMG}/${version}.bootfs.img"
	declare -g ROOTFS_IMAGE_FILE="${DESTIMG}/${version}.rootfs.img"

	# Extract partition offsets from the image using fdisk
	local img="${DESTIMG}/${version}.img"
	local sector_size=512

	local p1_start=$(fdisk -l "${img}" | grep "${img}1" | awk '{print $2}')
	local p1_sectors=$(fdisk -l "${img}" | grep "${img}1" | awk '{print $4}')
	local p2_start=$(fdisk -l "${img}" | grep "${img}2" | awk '{print $2}')
	local p2_sectors=$(fdisk -l "${img}" | grep "${img}2" | awk '{print $4}')

	display_alert "Extracting boot partition" "offset=${p1_start} sectors=${p1_sectors}" "info"
	dd if="${img}" of="${BOOTFS_IMAGE_FILE}" bs=${sector_size} skip=${p1_start} count=${p1_sectors} status=progress

	display_alert "Extracting rootfs partition" "offset=${p2_start} sectors=${p2_sectors}" "info"
	dd if="${img}" of="${ROOTFS_IMAGE_FILE}" bs=${sector_size} skip=${p2_start} count=${p2_sectors} status=progress

	rm -rf arduino-images
	mkdir -p arduino-images/flash
	cp -r "${QCOMBIN_DIR}/Agatti/arduino-uno-q/"* arduino-images/flash/
	cp "${QCOMBIN_DIR}/Agatti/prog_firehose_ddr.elf" arduino-images/flash/

	mkdir -p rootfs_mount
	local rootfs_loop=$(losetup -f --show "${ROOTFS_IMAGE_FILE}")
	mount ${rootfs_loop} rootfs_mount
	cp rootfs_mount/usr/lib/linux-u-boot-${BRANCH}-${BOARD}/boot.img arduino-images/flash/
	umount rootfs_mount
	losetup -d ${rootfs_loop}

	rm "${img}"

	mv ${BOOTFS_IMAGE_FILE} arduino-images/disk-sdcard.img.esp
	mv ${ROOTFS_IMAGE_FILE} arduino-images/disk-sdcard.img.root

	tar -cvf ${DESTIMG}/${version}.tar arduino-images
	rm -rf arduino-images

	return 0
}
