# Rockchip RK3288 quad core 2GB RAM SoC GBE WiFi eMMC
BOARD_NAME="Tinker Board"
BOARDFAMILY="rockchip"
BOARD_MAINTAINER="paolosabatino"
BOOTCONFIG="tinker-s-rk3288_defconfig"
DEFAULT_OVERLAYS="i2c1 i2c4 spi2 spidev2 uart1 uart2"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_SOC="rk3288"

function tinkerboard_uboot_postinst() {
	[[ $DEVICE == /dev/null ]] && exit 0
	if [[ -z $DEVICE ]]; then
		DEVICE="/dev/mmcblk0"
		# proceed to other options.
		[ ! -b $DEVICE ] && DEVICE="/dev/mmcblk1"
		[ ! -b $DEVICE ] && DEVICE="/dev/mmcblk2"
	fi
	[[ $(type -t setup_write_uboot_platform) == function ]] && setup_write_uboot_platform
	if [[ -b $DEVICE ]]; then
		echo "Updating u-boot on $DEVICE" >&2
		write_uboot_platform $DIR $DEVICE
		sync
	else
		echo "Device $DEVICE does not exist, skipping" >&2
	fi
}

function pre_package_uboot_image__tinkerboard_update_uboot_postinst_script() {
	postinst_functions+=('tinkerboard_uboot_postinst')
}
