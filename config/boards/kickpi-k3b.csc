# Rockchip RK3562 DDR3 eMMC GBE SWT6621S WLAN/BT
BOARD_NAME="KICKPI K3B"
BOARD_VENDOR="kickpi"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER="retro98boy"
INTRODUCED="2026"
BOOTCONFIG="kickpi-k3b-rk3562_defconfig"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3562-kickpi-k3b.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SOC="rk3562"
IMAGE_PARTITION_TABLE="gpt"
enable_extension "seekwave-swt6621s-dkms"
SWT6621S_TYPE="SDIO"
PACKAGE_LIST_BOARD="alsa-ucm-conf"

function post_family_config__kickpi-k3b() {
	declare -g OVERLAY_PREFIX="rk3562-kickpi-k3b"
	# Default DSI panel overlay.
	declare -g DEFAULT_OVERLAYS="sq101p-x4ei451-84h501"
}

function post_family_tweaks_bsp__kickpi-k3b() {
	display_alert "${BOARD}" "Installing ALSA UCM configuration files" "info"

	install -Dm644 "${SRC}/packages/bsp/kickpi-k3b/kickpi-k3b-HiFi.conf" \
		"${destination}/usr/share/alsa/ucm2/Rockchip/kickpi-k3b/kickpi-k3b-HiFi.conf"
	install -Dm644 "${SRC}/packages/bsp/kickpi-k3b/kickpi-k3b.conf" \
		"${destination}/usr/share/alsa/ucm2/Rockchip/kickpi-k3b/kickpi-k3b.conf"

	mkdir -p "${destination}/usr/share/alsa/ucm2/conf.d/kickpi-k3b"
	ln -sfv ../../Rockchip/kickpi-k3b/kickpi-k3b.conf \
		"${destination}/usr/share/alsa/ucm2/conf.d/kickpi-k3b/kickpi-k3b.conf"
}

function post_family_tweaks__kickpi-k3b() {
	echo -e "panel_simple\njadard_touch" > "${SDCARD}/etc/modules-load.d/panel.conf"
	# The JD9366 touch driver must be probed after the display driver.
	# Otherwise, I2C communication will fail.
	echo "softdep jadard_touch pre: panel_simple" > "${SDCARD}/etc/modprobe.d/jadard_touch-dependencies.conf"
}
