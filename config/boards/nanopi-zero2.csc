# Rockchip RK3528 quad core 1/2GB RAM SoC GBe eMMC USB2 USB-C PCIe 2.1
BOARD_NAME="NanoPi Zero2"
BOARD_VENDOR="friendlyelec"
BOARDFAMILY="rk35xx"
BOOTCONFIG="hinlink_rk3528_defconfig"
BOARD_MAINTAINER=""
KERNEL_TARGET="vendor,current,edge"
FULL_DESKTOP="no"
HAS_VIDEO_OUTPUT="no"
BOOT_FDT_FILE="rockchip/rk3528-nanopi-rev01.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOOTFS_TYPE="ext4"
BOOTSIZE="512"

# Mainline kernel (current/edge) uses a different DTB filename than vendor kernel
# and RK3528 debug UART is UART0 (ttyS0), not UART2 (ttyS2) like other RK35xx SoCs
function post_family_config__nanopi_zero2_mainline() {
	case "${BRANCH}" in
		current|edge)
			declare -g BOOT_FDT_FILE="rockchip/rk3528-nanopi-zero2.dtb"
			declare -g SERIALCON="ttyS0"
			display_alert "$BOARD" "Using ${BOOT_FDT_FILE} and SERIALCON=${SERIALCON} for ${BRANCH}" "info"
			;;
	esac
}

# Patch boot script: RK3528 NanoPi Zero2 uses UART0 (ttyS0) for serial console, not UART2 (ttyS2)
function post_family_tweaks__nanopi_zero2_serial_console() {
	case "${BRANCH}" in
		current|edge)
			display_alert "$BOARD" "Adjusting boot.cmd serial console to ttyS0 for ${BRANCH}" "info"
			sed -i 's/console=ttyS2,1500000/console=ttyS0,1500000/g' "${SDCARD}"/boot/boot.cmd
			mkimage -C none -A arm -T script -d "${SDCARD}"/boot/boot.cmd "${SDCARD}"/boot/boot.scr
			;;
	esac
}
