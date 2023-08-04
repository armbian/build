# Rockchip RK3399 hexa core 1-4GB SoC GBe eMMC USB3 WiFi/BT PoE miniDP USB host
BOARD_NAME="Rockpi 4C"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
BOOTCONFIG="rock-pi-4c-rk3399_defconfig"
KERNEL_TARGET="legacy,current,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-rock-pi-4c.dtb"
BOOT_SCENARIO="tpl-spl-blob"
BOOT_SUPPORT_SPI=yes

function post_family_tweaks_bsp__rockpi-4c_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}
