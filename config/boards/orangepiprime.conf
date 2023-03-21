# Allwinner H5 quad core 2GB RAM Wi-Fi/BT
BOARD_NAME="Orange Pi Prime"
BOARDFAMILY="sun50iw2"
BOOTCONFIG="orangepi_prime_defconfig"
DEFAULT_OVERLAYS="analog-codec"
KERNEL_TARGET="legacy,current,edge"
FULL_DESKTOP="yes"

function post_family_tweaks_bsp__orangepiprime_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}