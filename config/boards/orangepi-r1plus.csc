# Rockchip RK3328 quad core 1GB 2 x GBE USB2 SPI
BOARD_NAME="Orange Pi R1 Plus"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_r1_plus_rk3328_defconfig"
KERNEL_TARGET="current,edge"
DEFAULT_CONSOLE="serial"
MODULES="g_serial"
MODULES_BLACKLIST="rockchipdrm analogix_dp dw_mipi_dsi dw_hdmi gpu_sched lima hantro_vpu"
SERIALCON="ttyS2:1500000,ttyGS0"
HAS_VIDEO_OUTPUT="no"
BOOT_FDT_FILE="rockchip/rk3328-orangepi-r1-plus.dtb"

function post_family_tweaks__opi-r1plus_rename_USB_LAN() {
    display_alert "$BOARD" "Installing board tweaks" "info"

	# rename USB based network to lan0
	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="r8152", KERNEL=="eth1", NAME="lan0"' > $SDCARD/etc/udev/rules.d/70-rename-lan.rules

	return 0
}

function post_family_tweaks_bsp__orangepi-r1plus_BSP() {
    display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}