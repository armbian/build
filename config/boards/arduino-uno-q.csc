# Qualcomm QRB210 4 core 2/4GB RAM SoC USB-C
BOARD_NAME="Arduino UNO Q"
BOARDFAMILY="qrb2210"
BOARD_MAINTAINER="chainsx"
KERNEL_TARGET="edge"
BOOTCONFIG="qcom_defconfig"
BOOT_FDT_FILE="qcom/qrb2210-arduino-imola.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="loglevel=8 clk_ignore_unused pd_ignore_unused audit=0 deferred_probe_timeout=30"
BOOTFS_TYPE="fat"
BOOTSIZE="256"

declare -g BOARD_FIRMWARE_INSTALL="-full"

function post_family_tweaks__arduino-uno-q() {
	display_alert "Applying firmware"
	mkdir -p $SDCARD/lib/firmware/qcom/qcm2290/
	mkdir -p $SDCARD/lib/firmware/qcom/venus-6.0/

	cp -v "$SRC/packages/blobs/arduino/firmware/qca/apbtfw11.tlv" "$SDCARD/lib/firmware/qca/apbtfw11.tlv"
	cp -v "$SRC/packages/blobs/arduino/firmware/qca/apnv11.bin" "$SDCARD/lib/firmware/qca/apnv11.bin"
	cp -v "$SRC/packages/blobs/arduino/firmware/qcom/a702_sqe.fw" "$SDCARD/lib/firmware/qcom/a702_sqe.fw"

	cp -v "$SRC/packages/blobs/arduino/firmware/qcom/qcm2290/a702_zap.mbn" "$SDCARD/lib/firmware/qcom/qcm2290/a702_zap.mbn"
	cp -v "$SRC/packages/blobs/arduino/firmware/qcom/qcm2290/adspr.jsn" "$SDCARD/lib/firmware/qcom/qcm2290/adspr.jsn"
	cp -v "$SRC/packages/blobs/arduino/firmware/qcom/qcm2290/adspua.jsn" "$SDCARD/lib/firmware/qcom/qcm2290/adspua.jsn"
	cp -v "$SRC/packages/blobs/arduino/firmware/qcom/qcm2290/modemr.jsn" "$SDCARD/lib/firmware/qcom/qcm2290/modemr.jsn"
	cp -v "$SRC/packages/blobs/arduino/firmware/qcom/qcm2290/wlanmdsp.mbn" "$SDCARD/lib/firmware/qcom/qcm2290/wlanmdsp.mbn"
	cp -v "$SRC/packages/blobs/arduino/firmware/qcom/qcm2290/adsp.mbn" "$SDCARD/lib/firmware/qcom/qcm2290/adsp.mbn"
	cp -v "$SRC/packages/blobs/arduino/firmware/qcom/qcm2290/adsps.jsn" "$SDCARD/lib/firmware/qcom/qcm2290/adsps.jsn"
	cp -v "$SRC/packages/blobs/arduino/firmware/qcom/qcm2290/modem.mbn" "$SDCARD/lib/firmware/qcom/qcm2290/modem.mbn"
	cp -v "$SRC/packages/blobs/arduino/firmware/qcom/qcm2290/modemuw.jsn" "$SDCARD/lib/firmware/qcom/qcm2290/modemuw.jsn"
	cp -v "$SRC/packages/blobs/arduino/firmware/qcom/venus-6.0/venus.mbn" "$SDCARD/lib/firmware/qcom/venus-6.0/venus.mbn"

	# install extra packages for WiFi&Bt
	do_with_retries 3 chroot_sdcard_apt_get_update
	do_with_retries 3 chroot_sdcard_apt_get_install rmtfs qrtr-tools protection-domain-mapper tqftpserv bluetooth bluez
}

function post_family_tweaks_bsp__arduino-uno-q_bsp_firmware_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: firmware in initrd" "info"
	declare file_added_to_bsp_destination # will be filled in by add_file_from_stdin_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/initramfs-hook-qcm2290-fw" <<- 'FIRMWARE_HOOK'
		#!/bin/bash
		[[ "$1" == "prereqs" ]] && exit 0
		. /usr/share/initramfs-tools/hook-functions
		add_firmware "qcom/qcm2290/a702_zap.mbn" # extra one for gpu
		add_firmware "qcom/a702_sqe.fw" # extra one for dpu
	FIRMWARE_HOOK
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"
}
