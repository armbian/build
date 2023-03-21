# Allwinner H5 quad core 512MB RAM SoC Wi-Fi/BT
BOARD_NAME="Orange Pi Zero Plus 2"
BOARDFAMILY="sun50iw2"
BOOTCONFIG="orangepi_zero_plus2_defconfig"
MODULES_LEGACY="g_serial"
MODULES_CURRENT="g_serial"
DEFAULT_OVERLAYS="gpio-regulator-1.3v usbhost2 usbhost3"
HAS_VIDEO_OUTPUT="no"
SERIALCON="ttyS0,ttyGS0"
KERNEL_TARGET="legacy,current,edge"

function post_family_tweaks_bsp__orangepizeroplus2-h5_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}