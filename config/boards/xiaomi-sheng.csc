# Qualcomm SM8550 octa core 8/12/16GB tablet
declare -g BOARD_NAME="Xiaomi Pad 6S Pro"
declare -g BOARD_VENDOR="xiaomi"
declare -g BOARD_MAINTAINER="code002-2"
declare -g INTRODUCED="2024"
declare -g BOARDFAMILY="sm8550-sheng"
declare -g KERNEL_TARGET="edge,bleedingedge"
declare -g KERNEL_TEST_TARGET="edge,bleedingedge"
declare -g EXTRAWIFI="no"
declare -g BOOTCONFIG="none"
declare -g IMAGE_PARTITION_TABLE="gpt"
declare -g -a ABL_DTB_LIST=("sm8550-xiaomi-sheng")
declare -g BOOTIMG_CMDLINE_EXTRA="udmabuf.size_limit_mb=256 quiet"

# Use the full firmware, complete armbian/firmware (qcom/sm8550/sheng, a740_sqe.fw ...)
declare -g BOARD_FIRMWARE_INSTALL="-full"

function xiaomi-sheng_is_userspace_supported() {
	[[ "${RELEASE}" == "jammy" ]] && return 0
	[[ "${RELEASE}" == "trixie" ]] && return 0
	[[ "${RELEASE}" == "noble" ]] && return 0
	[[ "${RELEASE}" == "resolute" ]] && return 0
	return 1
}

function xiaomi-sheng_is_userspace_supported_alert() {
	if ! xiaomi-sheng_is_userspace_supported; then
		if [[ "${RELEASE}" != "" ]]; then
			display_alert "Missing userspace for ${BOARD}" "${RELEASE} does not have the userspace necessary to support the ${BOARD}" "warn"
		fi
		return 1
	fi
	return 0
}

function post_family_tweaks_bsp__xiaomi-sheng_firmware() {
	xiaomi-sheng_is_userspace_supported_alert || return 0

	display_alert "$BOARD" "Install firmwares for xiaomi sheng" "info"

	# alsa-ucm-conf profile for Xiaomi Pad 6S Pro, tplg is provided by armbian/firmware
	mkdir -p $destination/usr/share/alsa/ucm2/conf.d/sm8550
	install -Dm644 $SRC/packages/bsp/xiaomi-sheng/Xiaomi-Pad6SPro.conf $destination/usr/share/alsa/ucm2/Xiaomi/sheng/Xiaomi-Pad6SPro.conf
	install -Dm644 $SRC/packages/bsp/xiaomi-sheng/HiFi.conf $destination/usr/share/alsa/ucm2/Xiaomi/sheng/HiFi.conf
	ln -sfv ../../Xiaomi/sheng/Xiaomi-Pad6SPro.conf \
		"$destination/usr/share/alsa/ucm2/conf.d/sm8550/Xiaomi-Pad6SPro.conf"

	# WirePlumber: disable ACP so real ALSA sinks are created (otherwise
	# audio falls back to the Dummy Output sink on this DSP card)
	mkdir -p $destination/etc/wireplumber/wireplumber.conf.d/
	install -Dm644 $SRC/packages/bsp/xiaomi-sheng/90-alsa-dsp.conf \
		$destination/etc/wireplumber/wireplumber.conf.d/90-alsa-dsp.conf

	# Boot-time UCM init (loads HiFi verb + enables speaker amps)
	mkdir -p $destination/usr/local/bin/
	mkdir -p $destination/usr/lib/systemd/system/
	install -Dm755 $SRC/packages/bsp/xiaomi-sheng/sheng-ucm-init.sh \
		$destination/usr/local/bin/
	install -Dm644 $SRC/packages/bsp/xiaomi-sheng/sheng-ucm-init.service \
		$destination/usr/lib/systemd/system/

	# Xiaomi MiPPS/PPS charger authentication (edge kernel only)
	if [[ "$BRANCH" == "edge" ]]; then
		display_alert "$BOARD" "Install Xiaomi MiPPS charger auth" "info"
		mkdir -p $destination/usr/libexec/
		mkdir -p $destination/usr/lib/systemd/system/
		mkdir -p $destination/usr/lib/udev/rules.d/
		install -Dm755 $SRC/packages/bsp/xiaomi-sheng/xiaomi-mipps-auth \
			$destination/usr/libexec/xiaomi-mipps-auth
		install -Dm644 $SRC/packages/bsp/xiaomi-sheng/xiaomi-mipps-auth.service \
			$destination/usr/lib/systemd/system/xiaomi-mipps-auth.service
		install -Dm644 $SRC/packages/bsp/xiaomi-sheng/90-xiaomi-mipps-auth.rules \
			$destination/usr/lib/udev/rules.d/90-xiaomi-mipps-auth.rules
	fi

	# USB Gadget Network service
	mkdir -p $destination/usr/local/bin/
	mkdir -p $destination/usr/lib/systemd/system/
	mkdir -p $destination/etc/initramfs-tools/scripts/init-bottom/
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/setup-usbgadget-network.sh $destination/usr/local/bin/
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/remove-usbgadget-network.sh $destination/usr/local/bin/
	install -Dm644 $SRC/packages/bsp/usb-gadget-network/usbgadget-rndis.service $destination/usr/lib/systemd/system/
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/usb-gadget-initramfs-hook $destination/etc/initramfs-tools/hooks/usb-gadget
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/usb-gadget-initramfs-premount $destination/etc/initramfs-tools/scripts/init-premount/usb-gadget
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/dropbear $destination/etc/initramfs-tools/scripts/init-premount/
	install -Dm655 $SRC/packages/bsp/usb-gadget-network/kill-dropbear $destination/etc/initramfs-tools/scripts/init-bottom/

	# Bluetooth MAC addr setup service
	install -Dm655 $SRC/packages/bsp/generate-bt-mac-addr/bt-fixed-mac.sh $destination/usr/local/bin/
	install -Dm644 $SRC/packages/bsp/generate-bt-mac-addr/bt-fixed-mac.service $destination/usr/lib/systemd/system/

	# Kernel postinst script to update abl boot partition
	install -Dm655 $SRC/packages/bsp/xiaomi-sheng/zz-update-abl-kernel $destination/etc/kernel/postinst.d/

	return 0
}

function post_family_tweaks__xiaomi-sheng_enable_services() {
	xiaomi-sheng_is_userspace_supported_alert || return 0

	# we need unudhcpd from armbian repo, so enable it
	mv "${SDCARD}"/etc/apt/sources.list.d/armbian.sources.disabled "${SDCARD}"/etc/apt/sources.list.d/armbian.sources

	do_with_retries 3 chroot_sdcard_apt_get_update
	display_alert "$BOARD" "Installing board tweaks" "info"
	do_with_retries 3 chroot_sdcard_apt_get_install alsa-ucm-conf qbootctl qrtr-tools unudhcpd mkbootimg dropbear-bin

	# disable armbian repo back
	mv "${SDCARD}"/etc/apt/sources.list.d/armbian.sources "${SDCARD}"/etc/apt/sources.list.d/armbian.sources.disabled
	do_with_retries 3 chroot_sdcard_apt_get_update

	chroot_sdcard systemctl enable qbootctl.service
	chroot_sdcard systemctl enable usbgadget-rndis.service
	chroot_sdcard systemctl enable bt-fixed-mac.service
	chroot_sdcard systemctl enable sheng-ucm-init.service

	# Xiaomi MiPPS/PPS charger authentication (edge kernel only)
	if [[ "$BRANCH" == "edge" ]]; then
		chroot_sdcard systemctl enable xiaomi-mipps-auth.service
	fi
	return 0
}

function post_family_tweaks_bsp__xiaomi-sheng_bsp_firmware_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: firmware in initrd" "info"
	declare file_added_to_bsp_destination # will be filled in by add_file_from_stdin_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/xiaomi-sheng-firmware" <<- 'FIRMWARE_HOOK'
		#!/bin/bash
		[[ "$1" == "prereqs" ]] && exit 0
		. /usr/share/initramfs-tools/hook-functions
		for f in $(find /lib/firmware/qcom/sm8550/sheng -type f) ; do
			add_firmware "${f#/lib/firmware/}"
		done
		add_firmware "qcom/sm8550/Xiaomi-Pad6SPro-tplg.bin" # extra one for sound machine
		add_firmware "qcom/a740_sqe.fw" # extra one for dpu
		add_firmware "qcom/gmu_gen70200.bin" # extra one for gpu
		# Extra one for wifi
		for f in $(find /lib/firmware/ath12k/WCN7850 -type f) ; do
			add_firmware "${f#/lib/firmware/}"
		done
		# Extra one for bt
		for f in $(find /lib/firmware/qca -type f) ; do
			add_firmware "${f#/lib/firmware/}"
		done
	FIRMWARE_HOOK
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"
}

## Modules, required to boot, add them to initrd
function post_family_tweaks_bsp__xiaomi-sheng_bsp_modules_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: modules in initrd" "info"
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/modules" <<- 'EXTRA_MODULES'
		spi-geni-qcom
		nt36532e_ts
	EXTRA_MODULES
}
