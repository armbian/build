# Rockchip RV1106 single core 128-256MB SoC 1x100MBe NAND USB2
BOARD_NAME="Luckfox Pico Pro / Pico Max"
BOARD_VENDOR="luckfox"
BOARDFAMILY="rockchip-rv1106"
BOOTCONFIG="luckfox_rv1106_uboot_defconfig"
BOARD_MAINTAINER=""
KERNEL_TARGET="vendor"
BOOT_FDT_FILE="rv1106g-luckfox-pico-pro-max.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SOC="rv1106"

# Board has 128MB - 256MB RAM; use 'lowmem' extension to optimize for this.
enable_extension "lowmem"
