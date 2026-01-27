# Amlogic S905L-B 1GB RAM 8GB eMMC microSD FE USB2 RTL8189FTV WiFi
BOARD_NAME="BesTV R3300-L"
BOARD_VENDOR="amlogic"
BOARDFAMILY="meson-gxl"
BOARD_MAINTAINER="retro98boy"
BOOTCONFIG="bestv-r3300-l_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
SERIALCON="ttyAML0"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="amlogic/meson-gxl-s905x-bestv-r3300-l.dtb"
PACKAGE_LIST_BOARD="alsa-ucm-conf" # Contain ALSA UCM top-level configuration file
BOOTBRANCH_BOARD="tag:v2026.01"
BOOTPATCHDIR="v2026.01"

enable_extension "gxlimg"
enable_extension "amlogic-fip-blobs"

function post_family_config__use_repacked_fip() {
	declare -g UBOOT_TARGET_MAP="u-boot.bin"
	unset write_uboot_platform

	function write_uboot_platform() {
		dd if="$1/u-boot.bin" of="$2" bs=512 seek=1 conv=fsync,notrunc 2>&1
	}
}

function post_uboot_custom_postprocess__repack_vendor_fip_with_mainline_uboot() {
	gxlimg_repack_fip_with_new_uboot \
		"${SRC}/cache/sources/amlogic-fip-blobs/bestv-r3300-l/bootloader.PARTITION" \
		gxl
}

function post_family_tweaks_bsp__bestv-r3300-l() {
	display_alert "${BOARD}" "Installing ALSA UCM configuration files" "info"

	# Use ALSA UCM via CLI:
	# alsactl init && alsaucm set _verb "HiFi" set _enadev "HDMI"
	# or
	# alsactl init && alsaucm set _verb "HiFi" set _enadev "Lineout"
	# playback: aplay -D plughw:S905XP212,0 /usr/share/sounds/alsa/Front_Center.wav

	install -Dm644 "${SRC}/packages/bsp/S905X-P212/S905X-P212-HiFi.conf" \
		"${destination}/usr/share/alsa/ucm2/Amlogic/gx-sound-card/S905X-P212-HiFi.conf"
	install -Dm644 "${SRC}/packages/bsp/S905X-P212/S905X-P212.conf" \
		"${destination}/usr/share/alsa/ucm2/Amlogic/gx-sound-card/S905X-P212.conf"

	if [ ! -d "${destination}/usr/share/alsa/ucm2/conf.d/gx-sound-card" ]; then
		mkdir -p "${destination}/usr/share/alsa/ucm2/conf.d/gx-sound-card"
	fi
	ln -sfv /usr/share/alsa/ucm2/Amlogic/gx-sound-card/S905X-P212.conf \
		"${destination}/usr/share/alsa/ucm2/conf.d/gx-sound-card/S905X-P212.conf"
}
