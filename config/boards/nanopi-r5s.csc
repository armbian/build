# Rockchip RK3568 quad core 4GB RAM eMMC NVMe 2x USB3 1x GbE 2x 2.5GbE
BOARD_NAME="NanoPi R5S"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="utlark"
BOOT_SOC="rk3568"
KERNEL_TARGET="current,edge"
BOOT_FDT_FILE="rockchip/rk3568-nanopi-r5s.dtb"
SRC_EXTLINUX="no"
ASOUND_STATE="asound.state.station-m2" # TODO verify me
IMAGE_PARTITION_TABLE="gpt"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"

BOOTBRANCH_BOARD="tag:v2024.04-rc3"
BOOTPATCHDIR="v2024.04"
BOOTCONFIG="nanopi-r5s-rk3568_defconfig"

OVERLAY_PREFIX="rockchip-rk3568"
DEFAULT_OVERLAYS="nanopi-r5s-leds"

DDR_BLOB="rk35/rk3568_ddr_1560MHz_v1.18.bin"
BL31_BLOB="rk35/rk3568_bl31_v1.43.elf"

function post_family_config__uboot_config() {
	display_alert "$BOARD" "u-boot ${BOOTBRANCH_BOARD} overrides" "info"
	BOOTDELAY=2 # Wait for UART interrupt to enter UMS/RockUSB mode etc
	UBOOT_TARGET_MAP="ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB} BL31=$RKBIN_DIR/$BL31_BLOB spl/u-boot-spl u-boot.bin flash.bin;;idbloader.img u-boot.itb"
}

function post_family_tweaks__nanopir5s_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming interfaces WAN LAN1 LAN2" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="fe2a0000.ethernet", NAME:="wan"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0000:01:00.0", NAME:="lan1"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0001:01:00.0", NAME:="lan2"
	EOF
}
