# Rockchip RK3399 hexa core 2G/4GB RAM SoC GBE eMMC mPCI USB3 WiFi/BT
BOARD_NAME="Orange Pi RK3399"
BOARDFAMILY="rk3399"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi-rk3399_defconfig"
KERNEL_TARGET="legacy,current,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"

function post_family_tweaks_bsp__orangepi-rk3399_BSP() {
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