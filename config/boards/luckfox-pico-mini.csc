# Rockchip RV1103 single core 64MB SoC 1x100MBe NAND USB2
BOARD_NAME="Luckfox Pico Mini"
BOARDFAMILY="rockchip"
BOOTCONFIG="luckfox_rv1106_uboot_defconfig"
BOARD_MAINTAINER="vidplace7"
KERNEL_TARGET="vendor"
BOOT_FDT_FILE="rv1103g-luckfox-pico-mini.dtb"
IMAGE_PARTITION_TABLE="gpt"
SERIAL="ttyFIQ0"
# RV1103 but uses RV1106 blobs (doesn't work with RV1103 blobs)
BOOT_SOC="rv1106"
DDR_BLOB="rv11/rv1106_ddr_924MHz_v1.15.bin"
TEE_BLOB="rv11/rv1106_tee_ta_v1.13.bin"
USBPLUG_BLOB="rv11/rv1106_usbplug_v1.09.bin"
