# Realtek RTD1296 quad core 2GB RAM 8GB eMMC 2x GbE 2x SATA HDMI-in HDMI-out
BOARD_NAME="BananaPi W2"
BOARD_VENDOR="sinovoip"
BOARDFAMILY="realtek-rtd129x"
BOARD_MAINTAINER="igorpecovnik"
INTRODUCED="2018"
BOOTCONFIG="bananapi-w2_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current,edge"
BOOT_FDT_FILE="realtek/rtd1296-bananapi-w2.dtb"

# eth0: the SoC's MAC, next to the USB ports. eth1: port 5 of the NAT engine.
function post_family_tweaks__bananapiw2_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming interfaces eth0 eth1" "info"
	mkdir -p "${SDCARD}"/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="98016000.ethernet", NAME:="eth0"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="98060000.ethernet", NAME:="eth1"
	EOF
}

# Red LED: heartbeat, set in the DT. Green and blue: link and traffic of eth0 and eth1.
function post_family_tweaks_bsp__bananapiw2_leds() {
	display_alert "$BOARD" "Creating board support LEDs config" "info"
	cat <<- EOF > "${destination}"/etc/armbian-leds.conf
		[/sys/class/leds/green:lan-0]
		trigger=netdev
		interval=50
		link=1
		tx=1
		rx=1
		device_name=eth0

		[/sys/class/leds/blue:lan-1]
		trigger=netdev
		interval=50
		link=1
		tx=1
		rx=1
		device_name=eth1
	EOF
}
