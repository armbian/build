# Rockchip RK3399 hexa core 1-4GB SoC GBe eMMC USB3 WiFi/BT PoE
BOARD_NAME="Rockpi 4B"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
BOOTCONFIG="rock-pi-4-rk3399_defconfig"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-rock-pi-4b.dtb"
BOOT_SCENARIO="tpl-spl-blob"
BOOT_SUPPORT_SPI=yes
DDR_BLOB="rk33/rk3399_ddr_933MHz_v1.20.bin"

function post_family_tweaks_bsp__rockpi-4b_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}
