# Allwinner A733 octa core 2-16GB RAM GBE USB3 WiFi/BT NVMe eMMC
BOARD_NAME="Orange Pi 4 Pro"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun60iw2"
BOARD_MAINTAINER="shkolnik"
INTRODUCED="2025"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
IMAGE_PARTITION_TABLE="msdos"

BOOT_FDT_FILE="allwinner/sun60i-a733-orangepi-4-pro.dtb"
SUNXI_BOOT0_SDCARD_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_sdcard_orangepi4pro.fex"
SUNXI_BOOT0_SPINOR_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_spinor_orangepi4pro.fex"
SUNXI_SYS_CONFIG_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/sys_config_orangepi.fex"

# AIC8800D80 combo: BT is UART HCI on ttyS1 and needs userspace bring-up
SUN60IW2_UART_BT="yes"

# Invalidate U-Boot cache if any of the blobs change
UBOOT_HASH_EXTRA="$(cat "${SUNXI_BOOT0_SDCARD_FEX}" "${SUNXI_BOOT0_SPINOR_FEX}" "${SUNXI_SYS_CONFIG_FEX}" | sha256sum | cut -d' ' -f1)"

# The 4 Pro has 16 MB SPI-NOR; support writing the bootloader to MTD
function write_uboot_platform_mtd() {
	local SCRIPT_DIR="$1"   # dir holding boot0_spinor.fex + boot_package.fex
	flash_erase /dev/mtd0 0 0
	mtd_debug write /dev/mtd0 0      "$(stat -c%s "$SCRIPT_DIR/boot0_spinor.fex")" "$SCRIPT_DIR/boot0_spinor.fex"
	mtd_debug write /dev/mtd0 262144 "$(stat -c%s "$SCRIPT_DIR/boot_package.fex")" "$SCRIPT_DIR/boot_package.fex"
	sync
}
