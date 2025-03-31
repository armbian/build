# Rockchip RK3528 quad core 1-2GB SoC 2xGBe 8GB eMMC
BOARD_NAME="Radxa E20C"
BOARDFAMILY="rk35xx"
BOOTCONFIG="radxa_e20c_rk3528_defconfig"
BOARD_MAINTAINER="mattx433"
KERNEL_TARGET="vendor"
FULL_DESKTOP="no"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3528-radxa-e20c.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"

function post_family_tweaks_bsp__enable_leds_radxa-e20c() {
	display_alert "Creating board support LEDs config for $BOARD"
	cat <<- EOF > "${destination}"/etc/armbian-leds.conf
		[/sys/class/leds/lan-led]
		trigger=netdev
		interval=50
		brightness=1
		link=1
		tx=1
		rx=1
		device_name=end1

		[/sys/class/leds/mmc1::]
		trigger=mmc1
		brightness=1

		[/sys/class/leds/sys-led]
		trigger=heartbeat
		brightness=1
		invert=0

		[/sys/class/leds/wan-led]
		trigger=netdev
		interval=50
		brightness=1
		link=1
		tx=1
		rx=1
		device_name=enp1s0
	EOF
}
