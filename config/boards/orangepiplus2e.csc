# Allwinner H3 quad core 2GB RAM WiFi GBE eMMC
BOARD_NAME="Orange Pi+ 2E"
BOARDFAMILY="sun8i"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_plus2e_defconfig"
KERNEL_TARGET="legacy,current,edge"
FULL_DESKTOP="yes"

function post_family_tweaks_bsp__orangepiplus2e_BSP() {
	display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}
