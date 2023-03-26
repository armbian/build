# Allwinner H3 quad core 512MB RAM WiFi
BOARD_NAME="Orange Pi Lite"
BOARDFAMILY="sun8i"
BOOTCONFIG="orangepi_lite_defconfig"
MODULES_LEGACY="g_serial"
MODULES_CURRENT="g_serial"
KERNEL_TARGET="legacy,current,edge"

function post_family_tweaks_bsp__orangepilite_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}
