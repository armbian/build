# Rockchip RK3568 quad core 4GB RAM eMMC USB3 2x 2.5GbE
BOARD_NAME="NanoPi R5C"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
BOOT_SOC="rk3568"
KERNEL_TARGET="current,edge"
BOOT_FDT_FILE="rockchip/rk3568-nanopi-r5c.dtb"
SRC_EXTLINUX="no"
ASOUND_STATE="asound.state.station-m2" # TODO verify me
IMAGE_PARTITION_TABLE="gpt"
FULL_DESKTOP="no"
BOOT_LOGO="desktop"

BOOTBRANCH_BOARD="tag:v2024.04-rc3"
BOOTPATCHDIR="v2024.04"
BOOTCONFIG="nanopi-r5c-rk3568_defconfig"

OVERLAY_PREFIX="rockchip-rk3568"
DEFAULT_OVERLAYS="nanopi-r5c-leds"

DDR_BLOB="rk35/rk3568_ddr_1560MHz_v1.18.bin"
BL31_BLOB="rk35/rk3568_bl31_v1.43.elf"

function post_family_config__uboot_config() {
	display_alert "$BOARD" "u-boot ${BOOTBRANCH_BOARD} overrides" "info"
	BOOTDELAY=2 # Wait for UART interrupt to enter UMS/RockUSB mode etc
    UBOOT_TARGET_MAP="ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB} BL31=$RKBIN_DIR/$BL31_BLOB spl/u-boot-spl u-boot.bin flash.bin;;idbloader.img u-boot.itb"
}

function add_host_dependencies__new_uboot_wants_python3() {
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} python3-pyelftools" # @TODO: convert to array later
}

function post_family_tweaks__nanopir5c_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming interfaces WAN LAN" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0001:01:00.0", NAME:="lan"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0002:01:00.0", NAME:="wan"
	EOF
}
