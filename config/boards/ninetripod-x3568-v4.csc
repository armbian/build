# Rockchip RK3568 quad core 2GB-8GB RAM SoC 2 x GBE eMMC USB3 WiFi/BT PCIe SATA NVMe
BOARD_NAME="NineTripod X3568 v4"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="rbqvq"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3568-ninetripod-x3568-v4.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"

ASOUND_STATE="asound.state.station-m2" # TODO verify me

OVERLAY_PREFIX="rk3568-ninetripod-x3568-v4"

# Mainline U-Boot
function post_family_config__x3568_v4_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	DDR_BLOB="rk35/rk3568_ddr_1560MHz_v1.21.bin"
	BL31_BLOB="rk35/rk3568_bl31_v1.44.elf"

	declare -g BOOTCONFIG="ninetripod-x3568-v4-rk3568_defconfig"
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git" # We ❤️ Mainline U-Boot
	declare -g BOOTBRANCH="tag:v2025.10"
	declare -g BOOTPATCHDIR="v2025.10/board_${BOARD}"

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}

function post_family_tweaks__x3568_v4_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming interfaces" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="fe010000.ethernet", NAME:="eth0"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="fe2a0000.ethernet", NAME:="eth1"
	EOF
}
