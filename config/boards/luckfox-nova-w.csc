BOARD_NAME="Luckfox Nova W"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="nikvoid"

BOOT_SOC="rk3308"
BOOTCONFIG="luckfox-nova-w_rk3308b_defconfig"
BOOT_FDT_FILE="rockchip/rk3308-luckfox-nova-w.dtb"
# eMMC works properly only in vendor branch
KERNEL_TARGET="vendor"
KERNELSOURCE='https://github.com/armbian/linux-rockchip.git'
KERNELBRANCH='branch:rk-6.1-rkr5.1'
KERNELPATCHDIR='rockchip64-vendor-6.1'
KERNEL_MAJOR_MINOR="6.1"
LINUXFAMILY="rockchip64"
LINUXCONFIG="linux-luckfox-nova-w-rk3308-vendor"

DEFAULT_CONSOLE="serial"
SERIALCON="ttyS4"
MODULES="aic8800_fdrv"
MODULES_BLACKLIST="rockchipdrm analogix_dp dw_mipi_dsi dw_hdmi gpu_sched lima hantro_vpu panfrost"
HAS_VIDEO_OUTPUT="no"

BOOTBRANCH_BOARD="tag:v2025.04"
BOOTPATCHDIR="v2025.04"
IMAGE_PARTITION_TABLE="gpt"

BOOT_SCENARIO="binman"
DDR_BLOB="rk33/rk3308_ddr_589MHz_uart4_m0_v2.07.bin"
BL31_BLOB="rk33/rk3308_bl31_v2.26.elf"
MINILOADER_BLOB="rk33/rk3308_miniloader_v1.39.bin"

FORCE_UBOOT_UPDATE="yes"
OVERLAY_PREFIX="rk3308-luckfox-nova"

function post_family_config__bootscript() {
	declare -g BOOTSCRIPT="boot-rockchip64-ttyS4.cmd:boot.cmd"
}

function pre_install_kernel_debs__enforce_cma() {
	# Set CMA to 16 megabytes, to provide more usable RAM since board
	# has usually a small amount of DRAM (512MB)
	display_alert "$BOARD" "set CMA size to 16MB due to small DRAM size"
	run_host_command_logged echo "extraargs=cma=16M" ">>" "${SDCARD}"/boot/armbianEnv.txt

	return 0
}

function post_family_tweaks__move_wlan_fw() {
	mv "${SDCARD}/lib/firmware/aic8800/SDIO/aic8800DC" "${SDCARD}/lib/firmware/aic8800/SDIO/aic8800dc"
}
