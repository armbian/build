# Allwinner H6 quad core 2GB RAM SoC GBE USB3
BOARD_NAME="Orange Pi 3 LTS"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun50iw6"
BOARD_MAINTAINER=""
BOOT_FDT_FILE="sun50i-h6-orangepi-3-lts.dtb"
BOOTCONFIG="orangepi_3_lts_defconfig"
BOOT_LOGO="desktop"
MODULES_BLACKLIST="sunxi_addr" # Still loads but later in the boot process
CRUSTCONFIG="orangepi_3_lts_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"

function post_family_config__use_orangepi3lts_uboot() {
	case $BRANCH in
		* )
			declare -g ATFBRANCH="tag:lts-v2.12.9"
			declare -g BOOTPATCHDIR="v2026.01"
			declare -g BOOTBRANCH_BOARD="tag:${BOOTPATCHDIR}"
			declare -g BOOTBRANCH="${BOOTBRANCH_BOARD}"
			;;
	esac
}

# UWE5622 Wireless
function post_family_tweaks_bsp__uwe5622_wireless() {
	if [[ -f "$SRC/packages/bsp/sunxi/sprd-bluetooth" ]] && \
	[[ -f "$SRC/packages/bsp/sunxi/aw859a-wifi.service" ]] && \
	[[ -f "$SRC/packages/blobs/bt/hciattach/hciattach_opi_${ARCH}_upstream" ]]; then
		display_alert "$BOARD" "Installing UWE5622 Tweaks" "info"
		mkdir -p "${destination}"/usr/bin
		mkdir -p "${destination}"/etc/systemd/system
		cp -f "$SRC/packages/bsp/sunxi/sprd-bluetooth" "${destination}"/usr/bin
		cp -f "$SRC/packages/blobs/bt/hciattach/hciattach_opi_${ARCH}_upstream" "${destination}"/usr/bin/hciattach_opi
		chmod +x "${destination}"/usr/bin/sprd-bluetooth
		chmod +x "${destination}"/usr/bin/hciattach_opi
		cat >  "${destination}"/etc/systemd/system/sprd-bluetooth.service <<- EOT
		[Unit]
		Description=SPRD Bluetooth
		After=bluetooth.service bluetooth.target

		[Service]
		Type=simple
		ExecStartPre=/usr/sbin/rfkill unblock all
		ExecStart=/usr/bin/sprd-bluetooth
		TimeoutSec=0
		RemainAfterExit=true

		[Install]
		WantedBy=multi-user.target
		EOT
		cp -f "$SRC/packages/bsp/sunxi/aw859a-wifi.service" "${destination}"/etc/systemd/system/
		mkdir -p "${destination}"/etc/modules-load.d
		# Add needed wireless modules
		cat > "${destination}"/etc/modules-load.d/uwe5622-wireless.conf <<- EOT
		hci_uart
		bnep
		rfcomm
		sprdbt_tty
		EOT
	fi
}

# Enable UWE5622 Wireless Services
function post_family_tweaks__enable_uwe5622_wireless_services() {
	display_alert "$BOARD" "Enabling UWE5622 Wireless Services" "info"
	chroot_sdcard systemctl --no-reload enable sprd-bluetooth.service
	chroot_sdcard systemctl --no-reload enable aw859a-wifi.service
}

function post_family_config__opi3lts_set_asoundstate_file() {
	declare -g ASOUND_STATE='asound.state.sun50iw6-current'
}

function post_family_tweaks__opi3lts_configure_pulse_audio() {
	if [[ $BUILD_DESKTOP == yes ]]; then
		sed -i "s/auto-profiles = yes/auto-profiles = no/" ${SDCARD}/usr/share/pulseaudio/alsa-mixer/profile-sets/default.conf
		echo "load-module module-alsa-sink device=hw:0,0 sink_name=AudioCodec-Playback sink_properties=\"device.description='Audio Codec'\"" >> ${SDCARD}/etc/pulse/default.pa
		echo "load-module module-alsa-sink device=hw:1,0 sink_name=HDMI-Playback sink_properties=\"device.description='HDMI Audio'\"" >> ${SDCARD}/etc/pulse/default.pa
	fi
}
