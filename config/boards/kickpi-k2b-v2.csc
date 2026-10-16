# Allwinner H618 quad core 2GB DDR3 RAM WiFi GbE USB3
BOARD_NAME="K2B V2.2 DDR3"
BOARD_VENDOR="kickpi"
BOARDFAMILY="sun50iw9-bpi"
BOARD_MAINTAINER="Novice-PG"
INTRODUCED="2026"
BOOTCONFIG="kickpi_k2b_v2_defconfig"
OVERLAY_PREFIX="sun50i-h616"
BOOT_FDT_FILE="sun50i-h618-kickpi-k2b-v2.dtb"
BOOT_LOGO="desktop"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"
BOOTBRANCH_BOARD="tag:v2026.10"
BOOTPATCHDIR="v2026.10-sunxi64"
# No runtime lib name here: it differs per release (libgpiod1 bookworm, libgpiod3
# trixie). libgpiod-dev depends on the right one; gpiod is the CLI tooling.
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools libgpiod-dev gpiod"
# Prebuilt FFmpeg v4l2-request (userspace app) lives in an extension per review; the
# extension adds its own libx264 runtime to the package list in its config hook.
ENABLE_EXTENSIONS="ffmpeg-v4l2-request"

# Seekwave SWT6621S (vs6621s) SDIO WiFi/BT: DKMS driver and firmware from the
# Novice-PG/swt6621s release. The chip needs no device-tree node; the SDIO
# power sequence in sun50i-h618-kickpi-k2b-v2.dts (PG18/PG19 reset-gpios)
# powers it. The extension builds the modules in the chroot.
enable_extension "swt6621s-dkms"

# KickPi ships a WiFi watchdog in their image; carry the fixed version
# (interface-name extraction bug caused ~94s periodic restarts, see
# WIFI-WATCHDOG-FIX.md in the PR description)
function post_family_tweaks_bsp__kickpi_k2b_v2_wifi_watchdog() {
	display_alert "$BOARD" "Installing KickPi K2B WiFi watchdog" "info"
	install -d "${destination}/usr/bin" "${destination}/usr/lib/systemd/system"
	install -m 0755 "${SRC}/packages/bsp/kickpi-k2b-v2/kickpi-wifi-watchdog.sh" \
		"${destination}/usr/bin/kickpi-wifi-watchdog.sh"
	install -m 0644 "${SRC}/packages/bsp/kickpi-k2b-v2/kickpi-wifi-watchdog.service" \
		"${destination}/usr/lib/systemd/system/kickpi-wifi-watchdog.service"
}

# Enable KickPi K2B V2 WiFi watchdog
function post_family_tweaks__enable_kickpi_k2b_v2_wifi_watchdog() {
	if chroot_sdcard test -f /usr/lib/systemd/system/kickpi-wifi-watchdog.service; then
		chroot_sdcard systemctl --no-reload enable kickpi-wifi-watchdog.service
	else
		display_alert "$BOARD" "kickpi-wifi-watchdog.service not found in image" "warn"
	fi
}

# Module load order for the SWT6621S stack: skw_sdio_lite probes SDIO
# 1ffe:6621, boots the chip and allocates the "sv6621s_wireless1" and
# "skwbt" platform devices. List swt6621s_wifi and skwbt explicitly: the
# platform device names get a ".N.auto" suffix (PLATFORM_DEVID_AUTO), so
# the kernel module autoloader never matches them on 6.18.
function post_family_tweaks_bsp__kickpi_k2b_v2_wifi_modules_load() {
	display_alert "$BOARD" "Installing SWT6621S module load order" "info"
	install -d "${destination}/etc/modules-load.d"
	install -m 0644 "${SRC}/packages/bsp/kickpi-k2b-v2/etc/modules-load.d/vs6621s-wifi.conf" \
		"${destination}/etc/modules-load.d/vs6621s-wifi.conf"
}
