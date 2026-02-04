# Rockchip RK3506G2 triple core 128MB SoC 1x100MBe NAND SD USB2
BOARD_NAME="Luckfox Lyra Plus"
BOARD_VENDOR="luckfox"
BOARDFAMILY="rockchip"
BOOTCONFIG="luckfox-lyra-rk3506_defconfig"
BOARD_MAINTAINER="vidplace7"
KERNEL_TARGET="vendor"
BOOT_FDT_FILE="rk3506g-luckfox-lyra-plus-sd.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
SERIALCON="ttyFIQ0"
BOOT_SOC="rk3506"
DDR_BLOB="rk35/rk3506_ddr_750MHz_v1.06.bin"

# Board only has 128MB RAM; use 'lowmem' extension to optimize for this.
enable_extension "lowmem"
