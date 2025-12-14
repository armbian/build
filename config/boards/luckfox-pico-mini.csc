# Rockchip RV1103 single core 64MB SoC 1x100MBe NAND USB2
BOARD_NAME="Luckfox Pico Mini"
BOARD_VENDOR="luckfox"
BOARDFAMILY="rockchip-rv1106"
BOOTCONFIG="luckfox_rv1106_uboot_defconfig"
BOARD_MAINTAINER="vidplace7"
KERNEL_TARGET="vendor"
BOOT_FDT_FILE="rv1103g-luckfox-pico-mini.dtb"
IMAGE_PARTITION_TABLE="gpt"
# RV1103 but uses RV1106 blobs (doesn't work with RV1103 blobs)
BOOT_SOC="rv1103"
DDR_BLOB="rv11/rv1106_ddr_924MHz_v1.15.bin"
TEE_BLOB="rv11/rv1106_tee_ta_v1.13.bin"
USBPLUG_BLOB="rv11/rv1106_usbplug_v1.09.bin"

# Board only has 64MB RAM; use 'lowmem' extension to optimize for this.
enable_extension "lowmem"
