# Rockchip RV1103G single core 64MB SoC 1x100MBe NAND USB2
BOARD_NAME="Luckfox Pico Mini"
BOARD_VENDOR="luckfox"
BOARDFAMILY="rockchip-rv1106"
BOOTCONFIG="luckfox_rv1106_uboot_defconfig"
BOARD_MAINTAINER="vidplace7"
INTRODUCED="2024"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
BOOT_FDT_FILE="rv1103g-luckfox-pico-mini.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SOC="rv1103g"

# Board only has 64MB RAM; use 'lowmem' extension to optimize for this.
enable_extension "lowmem"
