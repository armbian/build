# Rockchip RK3399 hexa core 4GB RAM SoC 2 x GBE 32GB eMMC USB3 USB-C
BOARD_NAME="NanoPi R4SE"
BOARDFAMILY="rockchip64" # Used to be rk3399
BOARD_MAINTAINER=""
BOOTCONFIG="nanopi-r4se-rk3399_defconfig"
KERNEL_TARGET="current,edge"
DEFAULT_CONSOLE="serial"
MODULES_BLACKLIST="rockchipdrm analogix_dp dw_mipi_dsi dw_hdmi gpu_sched lima hantro_vpu panfrost"
HAS_VIDEO_OUTPUT="no"
BOOTBRANCH_BOARD="tag:v2022.04"
BOOTPATCHDIR="u-boot-rockchip64-v2022.04"
