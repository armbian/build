# Allwinner A733 octa core 2-16GB RAM GBE USB3 WiFi/BT NVMe eMMC
BOARD_NAME="Orange Pi 4 Pro"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun60iw2"
BOARD_MAINTAINER="shkolnik"
INTRODUCED="2025"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
IMAGE_PARTITION_TABLE="msdos"

# --- Board-specific build configuration ---
BOOT_FDT_FILE="allwinner/sun60i-a733-orangepi-4-pro.dtb"
OVERLAY_PREFIX="sun60i-a733"
KERNELPATCHDIR="archive/sun60iw2-opi-vendor"

# Fetch the Orange Pi 4 Pro boot blobs and set the family's SUNXI_*_FEX vars.
function fetch_custom_uboot__orangepi4pro() {
	local blob_repo="https://raw.githubusercontent.com/orangepi-xunlong/orangepi-build"
	local blob_ref="7f776a209b72b92e8c6a06abc83b1e7597eef5af"
	local url_base="${blob_repo}/${blob_ref}/external/packages/pack-uboot/sun60iw2/bin"

	local work_dir="$(mktemp -d)"
	declare -g SUNXI_BOOT0_SDCARD_FEX="${work_dir}/boot0_sdcard.fex"
	declare -g SUNXI_BOOT0_SPINOR_FEX="${work_dir}/boot0_spinor.fex"
	declare -g SUNXI_SYS_CONFIG_FEX="${work_dir}/sys_config.fex"

	display_alert "Orange Pi 4 Pro: fetching DRAM blobs" "${blob_ref:0:12}" "info"
	run_host_command_logged wget -q -O "${SUNXI_BOOT0_SDCARD_FEX}" "${url_base}/boot0_sdcard_a733.fex"
	run_host_command_logged wget -q -O "${SUNXI_BOOT0_SPINOR_FEX}" "${url_base}/boot0_spinor_a733.fex"
	run_host_command_logged wget -q -O "${SUNXI_SYS_CONFIG_FEX}"  "${url_base}/sys_config/sys_config.fex"
}

function write_uboot_platform() {
	local SCRIPT_DIR="$1" DEVICE="$2"
	dd conv=notrunc,fsync status=none if="${SCRIPT_DIR}/boot0_sdcard.fex" of="${DEVICE}" bs=1k seek=8
	dd conv=notrunc,fsync status=none if="${SCRIPT_DIR}/boot_package.fex" of="${DEVICE}" bs=1k seek=16400
	sync "${DEVICE}"
}

function write_uboot_platform_mtd() {
	local SCRIPT_DIR="$1"   # dir holding boot0_spinor.fex + boot_package.fex
	flash_erase /dev/mtd0 0 0
	mtd_debug write /dev/mtd0 0      "$(stat -c%s "$SCRIPT_DIR/boot0_spinor.fex")" "$SCRIPT_DIR/boot0_spinor.fex"
	mtd_debug write /dev/mtd0 262144 "$(stat -c%s "$SCRIPT_DIR/boot_package.fex")" "$SCRIPT_DIR/boot_package.fex"
	sync
}
