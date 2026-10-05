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
BOOTBRANCH_BOARD="tag:v2026.07"
BOOTPATCHDIR="v2026.07-sunxi64"
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"
# libx264-164 = runtime for the prebuilt FFmpeg v4l2-request x264 encoder (installer
# hook at the bottom of this file). Ubuntu "resolute" renamed the x264 ABI so the
# package is not available there — on that release the whole prebuilt-FFmpeg install
# is skipped by the hook below, so the package must not be requested either.
if [[ "${RELEASE}" != "resolute" ]]; then
	PACKAGE_LIST_BOARD+=" libx264-164"
fi

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

# Install prebuilt FFmpeg v4l2-request (Kwiboo FFmpeg 8.1, cedrus HW decode) — the
# follow-up to #10902 ("Plan C"): artifact is a Release asset on the contributor fork
# (40 MB stays out of git); install is fail-soft (glibc >= 2.41 guard, download and
# verify failures only warn, image build always continues). See
# packages/bsp/kickpi-k2b-v2/install-ffmpeg-v4l2.sh for the implementation.
function post_family_tweaks__kickpi_k2b_v2_ffmpeg_v4l2() {
	# Prebuilt binaries link libx264.so.164 (trixie); resolute renamed the ABI, so
	# skip there instead of installing something that cannot run.
	if [[ "${RELEASE}" == "resolute" ]]; then
		display_alert "$BOARD" "Skipping prebuilt FFmpeg v4l2-request on ${RELEASE}" "warn"
		return 0
	fi
	display_alert "$BOARD" "Installing prebuilt FFmpeg v4l2-request (fail-soft)" "info"
	source "${SRC}/packages/bsp/kickpi-k2b-v2/install-ffmpeg-v4l2.sh"
}
