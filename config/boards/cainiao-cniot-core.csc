# Amlogic A311D 2GB RAM 16GB eMMC GBE USB3 RTL8822CS WiFi/BT
BOARD_NAME="CAINIAO CNIoT-CORE"
BOARD_VENDOR="amlogic"
BOARDFAMILY="meson-g12b"
BOARD_MAINTAINER="retro98boy"
BOOTCONFIG="cainiao-cniot-core_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
MODULES_BLACKLIST="simpledrm" # SimpleDRM conflicts with Panfrost on the CAINIAO CNIoT-CORE
FULL_DESKTOP="yes"
SERIALCON="ttyAML0"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="amlogic/meson-g12b-a311d-cainiao-cniot-core.dtb"
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
		"${SRC}/cache/sources/amlogic-fip-blobs/cainiao-cniot-core/DDR.USB" \
		g12b
}

function post_family_tweaks_bsp__cainiao-cniot-core() {
	display_alert "${BOARD}" "Installing ALSA UCM configuration files" "info"

	# Use ALSA UCM via CLI: alsactl init && alsaucm set _verb "HiFi" set _enadev "HDMI" set _enadev "Speaker"
	# playback via HDMI: aplay -D plughw:cainiaocniotcor,0 /usr/share/sounds/alsa/Front_Center.wav
	# playback via internal speaker: aplay -D plughw:cainiaocniotcor,1 /usr/share/sounds/alsa/Front_Center.wav

	install -Dm644 "${SRC}/packages/bsp/cainiao-cniot-core/cainiao-cniot-core-HiFi.conf" \
		"${destination}/usr/share/alsa/ucm2/Amlogic/axg-sound-card/cainiao-cniot-core-HiFi.conf"
	install -Dm644 "${SRC}/packages/bsp/cainiao-cniot-core/cainiao-cniot-core.conf" \
		"${destination}/usr/share/alsa/ucm2/Amlogic/axg-sound-card/cainiao-cniot-core.conf"

	if [ ! -d "${destination}/usr/share/alsa/ucm2/conf.d/axg-sound-card" ]; then
		mkdir -p "${destination}/usr/share/alsa/ucm2/conf.d/axg-sound-card"
	fi
	ln -sfv /usr/share/alsa/ucm2/Amlogic/axg-sound-card/cainiao-cniot-core.conf \
		"${destination}/usr/share/alsa/ucm2/conf.d/axg-sound-card/cainiao-cniot-core.conf"
}
