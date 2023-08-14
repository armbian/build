# Rockchip RK3399 hexa core 4GB RAM SoC GBE USB3 USB-C WiFi/BT eMMC NVMe
BOARD_NAME="NanoPC T4"
BOARDFAMILY="rockchip64"
BOOTCONFIG="nanopc-t4-rk3399_defconfig"
KERNEL_TARGET="current,edge"
FULL_DESKTOP="yes"
ASOUND_STATE="asound.state.rt5651"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-nanopc-t4.dtb"
BOOT_SCENARIO="spl-blobs"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS2,1500000 console=tty0"

function post_family_tweaks_bsp__nanopc-t4_BSP() {
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
