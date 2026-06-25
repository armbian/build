# Rockchip RK3506G2 triple core 128MB SoC 2x100MBe NAND SD USB2
BOARD_NAME="EByte ECB41-PGE"
BOARD_VENDOR="ebyte"
BOARDFAMILY="rockchip"
BOOTCONFIG="ebyte-ecb41-pge_defconfig"
BOARD_MAINTAINER="vidplace7"
INTRODUCED="2025"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
BOOT_FDT_FILE="rk3506g-ebyte-ecb41-pge.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SOC="rk3506"

# Board only has 128MB RAM; use 'lowmem' extension to optimize for this.
enable_extension "lowmem"
