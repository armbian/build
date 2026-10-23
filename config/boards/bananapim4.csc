# Realtek RTD1395 quad core 1GB/2GB RAM 8GB eMMC FE USB HDMI
BOARD_NAME="BananaPi M4"
BOARD_VENDOR="sinovoip"
BOARDFAMILY="realtek-rtd129x"
BOARD_MAINTAINER="igorpecovnik"
INTRODUCED="2019"
BOOTCONFIG="bananapi-m4_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
BOOT_FDT_FILE="realtek/rtd1395-bpi-m4.dtb"
# The vendor loader in SPI flash reads U-Boot from SD or eMMC sector 80.
RTD129X_EMMC_BOOTAREA="no"
# The RTD1395 build of the audio firmware, which runs the HDMI output
RTD129X_AUDIO_FW_FILE="bluecore-rtd1395.audio"

# eth0: the RJ45, the SoC's MAC with its embedded 10/100 PHY.
# wlan0: the RTL8821CU module on USB port 2 (bus 1, port 2).
function post_family_tweaks__bananapim4_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming interfaces eth0 wlan0" "info"
	mkdir -p "${SDCARD}"/etc/udev/rules.d/
	cat <<- EOF2 > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="98016000.ethernet", NAME:="eth0"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="1-2:1.2", DRIVERS=="rtw88_8821cu", NAME:="wlan0"
	EOF2
}
