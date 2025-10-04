# Rockchip RK3328 quad core 1GB-4GB 1xFE USB3 [WiFi]
BOARD_NAME="Dusun DSOM 010R SoM"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="paolosabatino"
BOOTCONFIG="dusun-dsom-010r-rk3328_defconfig"
BOOT_FDT_FILE="rockchip/rk3328-dusun-dsom-010r.dtb"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
DEFAULT_CONSOLE="serial"
DEFAULT_OVERLAYS="dusun-010r-rp3328b"  # Enable, by default, the RP3328B carrier board devices
BOOTBRANCH_BOARD="tag:v2025.10-rc5"
BOOTPATCHDIR="v2025.10"
BOOT_SCENARIO="binman-atf-mainline"
DDR_BLOB="rk33/rk3328_ddr_933MHz_v1.16.bin"

