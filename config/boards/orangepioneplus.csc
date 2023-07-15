# Allwinner H6 quad core 1GB RAM SoC GBE
BOARD_NAME="Orange Pi One+"
BOARDFAMILY="sun50iw6"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_one_plus_defconfig"
KERNEL_TARGET="legacy,current,edge"
CRUSTCONFIG="h6_defconfig"

function post_family_tweaks_bsp__orangepioneplus_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}
