# Allwinner H6 quad core 2GB RAM SoC GBE USB3
BOARD_NAME="Orange Pi 3 LTS"
BOARDFAMILY="sun50iw6"
BOOTCONFIG="orangepi_3_lts_defconfig"
KERNEL_TARGET="current,edge"
MODULES="sprdbt_tty sprdwl_ng"
MODULES_BLACKLIST_LEGACY="bcmdhd"
ATFBRANCH="tag:v2.2"

function post_family_tweaks_bsp__orangepi3-lts_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}