# Rockchip RK3528A quad core 1/2GB RAM SoC GBe eMMC USB3 GPIO header
# Hardware-verified: boot, GBe ethernet, USB (host mode), RTC, SD storage,
# LEDs, GPIO header (I2C5/UART1/SPI1). Not verified: eMMC (no module on hand),
# USB-C port. Not supported yet: audio (no RK3528 audio driver/DT upstream).
BOARD_NAME="NanoPi NEO3 Plus"
BOARD_VENDOR="friendlyelec"
BOARDFAMILY="rk35xx"
BOOTCONFIG="hinlink_rk3528_defconfig"
BOARD_MAINTAINER=""
INTRODUCED="2026"
KERNEL_TARGET="current,edge"
FULL_DESKTOP="no"
HAS_VIDEO_OUTPUT="no"
BOOT_FDT_FILE="rockchip/rk3528-nanopi-neo3-plus.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOOTFS_TYPE="ext4"
BOOTSIZE="512"

# RK3528 debug UART is UART0 (ttyS0), not UART2 (ttyS2) like other RK35xx SoCs
function post_family_config__nanopi_neo3_plus_mainline() {
	declare -g SERIALCON="ttyS0"
	display_alert "$BOARD" "Using ${BOOT_FDT_FILE} and SERIALCON=${SERIALCON}" "info"
}

# Patch boot script: RK3528 NanoPi NEO3 Plus uses UART0 (ttyS0) for serial console, not UART2 (ttyS2)
function post_family_tweaks__nanopi_neo3_plus_serial_console() {
	display_alert "$BOARD" "Adjusting boot.cmd serial console to ttyS0" "info"
	sed -i 's/console=ttyS2,1500000/console=ttyS0,1500000/g' "${SDCARD}"/boot/boot.cmd
	mkimage -C none -A arm -T script -d "${SDCARD}"/boot/boot.cmd "${SDCARD}"/boot/boot.scr
}
