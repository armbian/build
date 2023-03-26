# Allwinner H3 quad core 512MB RAM SoC Wi-Fi/BT
BOARD_NAME="Orange Pi Zero Plus 2"
BOARDFAMILY="sun8i"
BOOTCONFIG="orangepi_zero_plus2_h3_defconfig"
MODULES_LEGACY="g_serial"
MODULES_CURRENT="g_serial"
DEFAULT_OVERLAYS="usbhost2 usbhost3"
SERIALCON="ttyS0,ttyGS0"
KERNEL_TARGET="legacy,current,edge"

function post_family_tweaks_bsp__orangepizeroplus2_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}