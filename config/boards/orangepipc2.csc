# Allwinner H5 quad core 1GB RAM SoC GBE SPI
BOARD_NAME="Orange Pi PC2"
BOARDFAMILY="sun50iw2"
BOOTCONFIG="orangepi_pc2_defconfig"
KERNEL_TARGET="legacy,current,edge"
FULL_DESKTOP="yes"

function post_family_tweaks_bsp__orangepipc2_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}