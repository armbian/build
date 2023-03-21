# Rockchip RK3399 hexa core 1GB RAM SoC GBE eMMC USB3 USB-C WiFi/BT
BOARD_NAME="NanoPi Neo 4"
BOARDFAMILY="rk3399"
BOOTCONFIG="nanopi-neo4-rk3399_defconfig"
KERNEL_TARGET="legacy,current,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"

function post_family_tweaks_bsp__nanopineo4_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

		# need to swap chips in the service
		sed -i s%BCM4345C5%BCM4356A2%g $destination/lib/systemd/system/rk3399-bluetooth.service

	fi

	return 0
}