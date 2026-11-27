#!/usr/bin/env bash
# @description Converts the Armbian image into a QDL-flashable `.tar` archive for the Arduino UNO Q (Qualcomm QRB2210). Splits the boot and root partitions with `dd` and takes the U-Boot `boot.img` from the rootfs before unmount. Bundles Qualcomm firehose flash binaries fetched from the `armbian/qcombin` repo during image creation.

declare -g ARDUINO_BOOT_IMG=""

# Copy boot.img while the rootfs is still mounted: a LUKS root cannot be mounted later.
function pre_umount_final_image__900_save_arduino_boot_img() {
	ARDUINO_BOOT_IMG="${SDCARD}.arduino-boot.img"
	run_host_command_logged cp "${MOUNT}/usr/lib/linux-u-boot-${BRANCH}-${BOARD}/boot.img" "${ARDUINO_BOOT_IMG}"
}

# Convert standard Armbian image into a QDL-flashable archive for Arduino UNO Q
function post_build_image__900_convert_to_arduino_img() {
	[[ -z $version ]] && exit_with_error "version is not set"

	# Fetch the Qualcomm QDL flash binaries (qcombin) here, at the point of use.
	# This deliberately does NOT run at config time (post_family_config): that hook
	# also fires for download-artifact and config-dump-json, which run with a
	# throwaway/absent $HOME, so 'git config --global' inside fetch_from_repo fails
	# (exit 128) - and qcombin is only ever consumed when actually building an image.
	display_alert "Fetching qcombin" "${BOARD}" "info"
	fetch_from_repo "https://github.com/armbian/qcombin" "qcombin" "branch:main"

	display_alert "Creating QDL flash archive" "${version}" "info"

	local img="${DESTIMG}/${version}.img"
	local bootfs_img="${DESTIMG}/${version}.bootfs.img"
	local rootfs_img="${DESTIMG}/${version}.rootfs.img"
	local outdir="${DESTIMG}/arduino-images"

	# Extract partition offsets using sfdisk JSON output
	local p1_start p1_size p2_start p2_size
	p1_start=$(sfdisk -J "${img}" | python3 -c "import sys,json; p=json.load(sys.stdin)['partitiontable']['partitions']; print(p[0]['start'])")
	p1_size=$(sfdisk -J "${img}" | python3 -c "import sys,json; p=json.load(sys.stdin)['partitiontable']['partitions']; print(p[0]['size'])")
	p2_start=$(sfdisk -J "${img}" | python3 -c "import sys,json; p=json.load(sys.stdin)['partitiontable']['partitions']; print(p[1]['start'])")
	p2_size=$(sfdisk -J "${img}" | python3 -c "import sys,json; p=json.load(sys.stdin)['partitiontable']['partitions']; print(p[1]['size'])")

	display_alert "Extracting boot partition" "offset=${p1_start} sectors=${p1_size}" "info"
	run_host_command_logged dd if="${img}" of="${bootfs_img}" bs=512 skip="${p1_start}" count="${p1_size}" status=progress

	display_alert "Extracting rootfs partition" "offset=${p2_start} sectors=${p2_size}" "info"
	run_host_command_logged dd if="${img}" of="${rootfs_img}" bs=512 skip="${p2_start}" count="${p2_size}" status=progress

	# Assemble flash directory with qcombin binaries
	rm -rf "${outdir}"
	mkdir -p "${outdir}/flash"
	run_host_command_logged cp -r "${QCOMBIN_DIR}/Agatti/arduino-uno-q/"* "${outdir}/flash/"
	run_host_command_logged cp "${QCOMBIN_DIR}/Agatti/prog_firehose_ddr.elf" "${outdir}/flash/"

	run_host_command_logged mv "${ARDUINO_BOOT_IMG}" "${outdir}/flash/boot.img"

	# Replace raw image with flash archive
	rm "${img}"
	mv "${bootfs_img}" "${outdir}/disk-sdcard.img.esp"
	mv "${rootfs_img}" "${outdir}/disk-sdcard.img.root"

	display_alert "Creating archive" "${version}.tar" "info"
	tar -cf "${DESTIMG}/${version}.tar" -C "${DESTIMG}" arduino-images
	rm -rf "${outdir}"

	return 0
}
