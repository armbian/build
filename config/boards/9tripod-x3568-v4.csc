# Rockchip RK3568 quad core 2GB-8GB RAM SoC 2 x GBE eMMC USB3 WiFi/BT PCIe SATA NVMe
BOARD_NAME="9Tripod X3568 v4"
BOARD_VENDOR="rockchip"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="rbqvq"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_SOC="rk3568"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3568-9tripod-x3568-v4.dtb"
IMAGE_PARTITION_TABLE="gpt"
MODULES="ledtrig_netdev"

OVERLAY_PREFIX="rk3568-9tripod-x3568-v4"

# Mainline U-Boot
function post_family_config__9tripod_x3568_v4_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="9tripod-x3568-v4-rk3568_defconfig"
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2025.10"
	declare -g BOOTPATCHDIR="v2025.10/board_${BOARD}"

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}

function post_family_tweaks__9tripod_x3568_v4_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming interfaces" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="fe010000.ethernet", NAME:="eth0"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="fe2a0000.ethernet", NAME:="eth1"
	EOF
}

function post_family_tweaks_bsp__9tripod_x3568_v4_enable_leds() {
	display_alert "$BOARD" "Creating Board Support LED Config" "info"
	cat <<- EOF > "$destination"/etc/armbian-leds.conf
		[/sys/class/leds/stmmac-0:03:amber:lan]
		trigger=netdev
		interval=52
		link_10=1
		link_100=1
		link_1000=1
		tx=1
		rx=1
		device_name=eth1

		[/sys/class/leds/stmmac-0:03:green:lan]
		trigger=netdev
		interval=52
		link_10=1
		link_100=1
		link_1000=1
		tx=0
		rx=0
		device_name=eth1

		[/sys/class/leds/stmmac-1:02:amber:lan]
		trigger=netdev
		interval=52
		link_10=1
		link_100=1
		link_1000=1
		tx=1
		rx=1
		device_name=eth0

		[/sys/class/leds/stmmac-1:02:green:lan]
		trigger=netdev
		interval=52
		link_10=1
		link_100=1
		link_1000=1
		tx=0
		rx=0
		device_name=eth0
	EOF
}
