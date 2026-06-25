# Rockchip RK3308B quad core 512MB RAM 8GB eMMC 100M Ethernet USB-C OTG
BOARD_NAME="Luckfox Nova"
BOARD_VENDOR="luckfox"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="crackerjacques"
INTRODUCED="2026"

BOOT_SOC="rk3308"
BOOTCONFIG="luckfox-rk3308b-nova_defconfig"
BOOT_FDT_FILE="rockchip/rk3308-luckfox-nova.dtb"

KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"

DEFAULT_CONSOLE="serial"
SERIALCON="ttyS4"
HAS_VIDEO_OUTPUT="no"
MODULES_BLACKLIST="rockchipdrm analogix_dp dw_mipi_dsi dw_hdmi gpu_sched lima hantro_vpu panfrost"

BOOTBRANCH_BOARD="tag:v2026.07-rc4"
BOOTPATCHDIR="v2026.07"
BOOT_SCENARIO="binman"
BOOTFS_TYPE="ext4"
IMAGE_PARTITION_TABLE="gpt"
DDR_BLOB="rk33/rk3308_ddr_589MHz_uart4_m0_v2.07.bin"
BL31_BLOB="rk33/rk3308_bl31_v2.26.elf"
MINILOADER_BLOB="rk33/rk3308_miniloader_v1.39.bin"

FORCE_UBOOT_UPDATE="yes"
OVERLAY_PREFIX="rk3308-luckfox-nova"

# Board helper tools shipped via the bsp-cli package
# (config/optional/boards/luckfox-rk3308b-nova/_packages/bsp-cli/):
#   novaconfig (DT-overlay interface toggle), mictest, pdmtest, gpiocheck,
#   pwmtest, /etc/asound.conf. They need dtc (overlay compile) and alsa-utils.
PACKAGE_LIST_BOARD="device-tree-compiler alsa-utils"

function post_family_config__luckfox_rk3308b_nova_boot() {
	# debug console is uart4 (1500000n8)
	declare -g BOOTSCRIPT="boot-rockchip64-ttyS4.cmd:boot.cmd"
}

function pre_install_kernel_debs__luckfox_rk3308b_nova_cma() {
	display_alert "$BOARD" "set CMA size to 16MB due to small DRAM size"
	run_host_command_logged echo "extraargs=cma=16M" ">>" "${SDCARD}"/boot/armbianEnv.txt
}
