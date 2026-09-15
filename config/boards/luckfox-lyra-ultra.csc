# Rockchip RK3506B triple-core 512MB SoC, 100M Ethernet, eMMC, USB2
BOARD_NAME="Luckfox Lyra Ultra"
BOARD_VENDOR="luckfox"
BOARDFAMILY="rockchip"
BOARD_MAINTAINER="stevenjoezhang"
INTRODUCED="2026"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
BOOTCONFIG="luckfox-lyra-ultra-rk3506b_defconfig"
BOOT_FDT_FILE="rk3506b-luckfox-lyra-ultra.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SOC="rk3506b"
IMAGE_PARTITION_TABLE="gpt"

# Known limitation: CPU OPP/cpufreq is not working yet.
