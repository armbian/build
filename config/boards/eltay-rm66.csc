BOARD_NAME="ELTAY RM66"
BOARD_VENDOR="elron"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER="RiPetitor"
INTRODUCED="2026"
BOOTCONFIG="eltay-rm66-rk3566_defconfig"
BOOT_SOC="rk3566"
KERNEL_TARGET="current,vendor"
KERNEL_TEST_TARGET="current"
BOOT_FDT_FILE="rockchip/rk3566-eltay-rm66.dtb"
SERIALCON="ttyS2"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="binman"
BOOT_SUPPORT_SPI="no"

PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"

function post_family_config__eltay_rm66_uboot() {
	display_alert "$BOARD" "Mainline U-Boot v2026.07 (ELTAY BB CM4 reference)" "info"
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.07"
	declare -g BOOTPATCHDIR="v2026.07"
	declare -g BOOTDELAY=0
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin"
}

function post_family_config_branch_vendor__eltay_rm66_kernel() {
	[[ "${KERNEL_MAJOR_MINOR}" == "6.1" ]] || exit_with_error "Eltay RM66 vendor branch requires the Rockchip BSP 6.1 series"
	display_alert "$BOARD" "Vendor BSP 6.1 (family branch): NPU, Media and CAM1 enabled" "info"
}

function pre_install_kernel_debs__eltay_rm66_vendor_bootargs() {
	[[ "${BRANCH}" == "vendor" ]] || return 0
	display_alert "$BOARD" "Add pm_domains.always_on=1 to extraboardargs" "info"
	run_host_command_logged echo "extraboardargs=pm_domains.always_on=1" >> "${SDCARD}"/boot/armbianEnv.txt
	return 0
}
