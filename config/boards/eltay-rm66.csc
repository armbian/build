# Rockchip RK3566 quad-core ELTAY RM66 compute module
#
# Kernel branches:
#   current — mainline; the framework auto-tracks the newest 6.18.x tag.
#   vendor  — Rockchip BSP 6.1 from armbian/linux-rockchip, tracking the head
#             of branch rk-6.1-rkr5.1 (no commit pin). Selected for the camera
#             (CIF/ISP) and NPU (RKNPU) stack; the BSP DT under
#             patch/kernel/rk35xx-vendor-6.1/dt is generic only: camera/CSI/ISP
#             nodes are added after the CAM1 carrier wiring is validated.
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
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="binman"
BOOT_SUPPORT_SPI="no"

function post_family_config__eltay_rm66_uboot() {
	# Mainline U-Boot for both kernel branches; one generic RM66 DT in the FIT.
	# The rk35xx family defaults to the Radxa vendor U-Boot; this overrides it.
	display_alert "$BOARD" "EXPERIMENTAL: generic DT default; carrier wiring requires validation" "wrn"
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.01"
	declare -g BOOTPATCHDIR="v2026.01"
	declare -g BOOTDELAY=1
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
}

function post_family_config_branch_vendor__eltay_rm66_kernel() {
	[[ "${KERNEL_MAJOR_MINOR}" == "6.1" ]] || exit_with_error "Eltay RM66 vendor branch requires the Rockchip BSP 6.1 series"
	# Track the head of the vendor branch instead of pinning a commit, so the
	# BSP kernel follows Rockchip's rk-6.1-rkr5.1 updates. The family case
	# already sets KERNELSOURCE and KERNELPATCHDIR=rk35xx-vendor-6.1;
	# LINUXFAMILY falls back to rk35xx, so the kernel config is
	# linux-rk35xx-vendor (upstream-maintained) and packages are
	# *-vendor-rk35xx.
	declare -g KERNELBRANCH="branch:rk-6.1-rkr5.1"
	declare -g LINUXFAMILY="rk35xx"
	declare -g LINUXCONFIG="linux-rk35xx-vendor"
	display_alert "$BOARD" "EXPERIMENTAL vendor BSP 6.1: camera/NPU DT nodes are not enabled yet" "wrn"
}

function pre_install_kernel_debs__eltay_rm66_vendor_bootargs() {
	[[ "${BRANCH}" == "vendor" ]] || return 0
	display_alert "$BOARD" "Add pm_domains.always_on=1 to extraboardargs" "info"
	run_host_command_logged echo "extraboardargs=pm_domains.always_on=1" >> "${SDCARD}"/boot/armbianEnv.txt
	return 0
}
