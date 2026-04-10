#!/usr/bin/env bash

# Fetch Qualcomm flash binaries early in the build
function post_family_config__fetch_qcombin() {
	[[ "${CONFIG_DEFS_ONLY}" == "yes" ]] && return 0 # skip fetch during config-dump-json (no $HOME, no network needed)
	display_alert "Fetching qcombin" "${BOARD}" "info"
	fetch_from_repo "https://github.com/armbian/qcombin" "qcombin" "branch:main"
}

declare -g ARDUINO_ROOTFS_LOOP=""
declare -g ARDUINO_ROOTFS_MOUNT=""

# Convert standard Armbian image into a QDL-flashable archive for Arduino UNO Q
function post_build_image__900_convert_to_arduino_img() {
	[[ -z $version ]] && exit_with_error "version is not set"

	display_alert "Creating QDL flash archive" "${version}" "info"

	local img="${DESTIMG}/${version}.img"
	local bootfs_img="${DESTIMG}/${version}.bootfs.img"
	local rootfs_img="${DESTIMG}/${version}.rootfs.img"
	local outdir="${DESTIMG}/arduino-images"
	ARDUINO_ROOTFS_MOUNT="${DESTIMG}/rootfs_mount"

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

	# Extract boot.img (U-Boot) from rootfs
	mkdir -p "${ARDUINO_ROOTFS_MOUNT}"
	ARDUINO_ROOTFS_LOOP=$(losetup -f --show "${rootfs_img}")
	add_cleanup_handler "image_output_arduino_cleanup"
	mount "${ARDUINO_ROOTFS_LOOP}" "${ARDUINO_ROOTFS_MOUNT}"
	run_host_command_logged cp "${ARDUINO_ROOTFS_MOUNT}/usr/lib/linux-u-boot-${BRANCH}-${BOARD}/boot.img" "${outdir}/flash/"
	umount "${ARDUINO_ROOTFS_MOUNT}"
	losetup -d "${ARDUINO_ROOTFS_LOOP}"
	ARDUINO_ROOTFS_LOOP=""

	# Replace raw image with flash archive
	rm "${img}"
	mv "${bootfs_img}" "${outdir}/disk-sdcard.img.esp"
	mv "${rootfs_img}" "${outdir}/disk-sdcard.img.root"

	display_alert "Creating archive" "${version}.tar" "info"
	tar -cf "${DESTIMG}/${version}.tar" -C "${DESTIMG}" arduino-images
	rm -rf "${outdir}"

	return 0
}

function image_output_arduino_cleanup() {
	if [[ -n "${ARDUINO_ROOTFS_LOOP}" ]]; then
		umount "${ARDUINO_ROOTFS_MOUNT}" 2>/dev/null
		losetup -d "${ARDUINO_ROOTFS_LOOP}" 2>/dev/null
	fi
}
