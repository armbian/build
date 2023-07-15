# Allwinner H2+ quad core 256/512MB RAM SoC WiFi SPI
BOARD_NAME="Orange Pi Zero"
BOARDFAMILY="sun8i"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_zero_defconfig"
MODULES_CURRENT="g_serial"
MODULES_BLACKLIST="sunxi_cedrus"
DEFAULT_OVERLAYS="usbhost2 usbhost3 tve"
DEFAULT_CONSOLE="both"
HAS_VIDEO_OUTPUT="yes"
SERIALCON="ttyS0,ttyGS0"
KERNEL_TARGET="legacy,current,edge"

function post_family_tweaks_bsp__orangepizero_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}