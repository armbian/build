# Allwinner A64 quad core 1GB/2GB RAM SoC GBE WiFi/BT
BOARD_NAME="Orange Pi Win"
BOARDFAMILY="sun50iw1"
BOOTCONFIG="orangepi_win_defconfig"
KERNEL_TARGET="legacy,current,edge"

function post_family_tweaks_bsp__orangepiwin_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}