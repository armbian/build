# Rockchip RK3576 octa core 4-16GB 2x GbE eMMC HDMI WiFi USB3 3x M.2 (B/E/M-Key)

BOARD_NAME="Photonicat2"
BOARD_VENDOR="ariaboard"
BOARD_MAINTAINER="HackingGate"
BOARDFAMILY="rk35xx"
INTRODUCED="2025"
BOOT_SOC="rk3576"
BOOTCONFIG="photonicat2-rk3576_defconfig"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="no"
BOOT_FDT_FILE="rockchip/rk3576-photonicat2.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOARD_FIRMWARE_INSTALL="-full"
ENABLE_EXTENSIONS="radxa-aic8800,photonicat-pm"
AIC8800_TYPE="usb"

# Enable btrfs support in u-boot
enable_extension "uboot-btrfs"

# Mainline U-Boot
function post_family_config__photonicat2_mainline_uboot() {
	display_alert "$BOARD" "Using Mainline U-Boot v2026.04" "info"
	declare -g BOOTSOURCE='https://github.com/u-boot/u-boot.git'
	declare -g BOOTBRANCH='tag:v2026.04'
	declare -g BOOTPATCHDIR='v2026.04'
	declare -g BOOTDIR="u-boot-${BOARD}"

	# Use binman for Mainline U-Boot
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable legacy rockchip processing
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Custom write function for u-boot-rockchip.bin
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

# Install USB hub watchdog (recovers onboard USB hubs after warm-reboot drop)
function post_family_tweaks_bsp__install_photonicat2_usb_hub_watchdog() {
	display_alert "$BOARD" "Installing Photonicat2 USB hub watchdog" "info"

	local watchdog_dir="${SRC}/packages/bsp/photonicat2/usb-hub-watchdog"

	install -Dm 0755 "${watchdog_dir}/photonicat-usb-hub-watchdog-run" \
		"${destination}/usr/lib/armbian/photonicat2-usb-hub-watchdog-run"

	install -Dm 0644 "${watchdog_dir}/photonicat-usb-hub-watchdog.service" \
		"${destination}/usr/lib/systemd/system/photonicat-usb-hub-watchdog.service"

	install -Dm 0644 "${watchdog_dir}/photonicat-usb-hub-watchdog.timer" \
		"${destination}/usr/lib/systemd/system/photonicat-usb-hub-watchdog.timer"
}

function post_family_tweaks__enable_photonicat2_usb_hub_watchdog() {
	display_alert "$BOARD" "Enabling Photonicat2 USB hub watchdog" "info"

	if chroot_sdcard systemctl enable photonicat-usb-hub-watchdog.timer; then
		display_alert "$BOARD" "USB hub watchdog enabled" "info"
	else
		display_alert "$BOARD" "Failed to enable photonicat-usb-hub-watchdog.timer" "err"
		return 1
	fi
}
