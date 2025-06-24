# Amlogic A311D 2GB RAM 16GB eMMC GBE USB3 RTL8822CS WiFi/BT
BOARD_NAME="CAINIAO CNIoT-CORE"
BOARDFAMILY="meson-g12b"
BOARD_MAINTAINER=""
BOOTCONFIG="cainiao-cniot-core_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
MODULES_BLACKLIST="simpledrm" # SimpleDRM conflicts with Panfrost on the CAINIAO CNIoT-CORE
FULL_DESKTOP="yes"
SERIALCON="ttyAML0"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="amlogic/meson-g12b-a311d-cainiao-cniot-core.dtb"
PACKAGE_LIST_BOARD="alsa-ucm-conf" # Contain ALSA UCM top-level configuration file

BOOTBRANCH_BOARD="tag:v2025.04"
BOOTPATCHDIR="v2025.04" # This has a patch that adds support for CAINIAO CNIoT-CORE.

function post_family_config__use_repacked_fip() {
	declare -g UBOOT_TARGET_MAP="u-boot.bin"
	unset write_uboot_platform

	function write_uboot_platform() {
		dd if="$1/u-boot.bin" of="$2" bs=512 seek=1 conv=fsync 2>&1
	}
}

function fetch_sources_tools__get_vendor_fip_and_gxlimg_source() {
	fetch_from_repo "https://github.com/retro98boy/cainiao-cniot-core-linux.git" "cainiao-cniot-core-linux" "commit:30273c25aeabf75f609cff2c4fa7264335c295a8"
	fetch_from_repo "https://github.com/repk/gxlimg.git" "gxlimg" "commit:0d0e5ba9cf396d1338067e8dc37a8bcd2e6874f1"
}

function build_host_tools__install_gxlimg() {
	# Compile and install only if git commit hash changed
	cd "${SRC}/cache/sources/gxlimg" || exit
	# need to check if /usr/local/bin/gxlimg to detect new Docker containers with old cached sources
	if [[ ! -f .commit_id || $(git rev-parse @ 2> /dev/null) != $(< .commit_id) || ! -f /usr/local/bin/gxlimg ]]; then
		display_alert "Compiling" "gxlimg" "info"
		run_host_command_logged make distclean
		run_host_command_logged make
		install -Dm0755 gxlimg /usr/local/bin/gxlimg
		git rev-parse @ 2> /dev/null > .commit_id
	fi
}

function post_uboot_custom_postprocess__repack_vendor_fip_with_mainline_uboot() {
	display_alert "${BOARD}" "Repacking vendor FIP with mainline u-boot.bin" "info"

	BLOBS_DIR="${SRC}/cache/sources/cainiao-cniot-core-linux"
	EXTRACT_DIR="${BLOBS_DIR}/extract"
	AML_ENCRYPT="${SRC}/cache/sources/amlogic-boot-fip/khadas-vim3/aml_encrypt_g12b"

	if [ ! -f "$AML_ENCRYPT" ]; then
		display_alert "${BOARD}" "amlogic-boot-fip/khadas-vim3/aml_encrypt_g12b not exist" "err"
		exit 1
	fi

	mv u-boot.bin raw-u-boot.bin
	rm -f "${EXTRACT_DIR}/bl33.enc"
	# The current version of gxlimg has a problem with the handling of bl3x,
	# which may cause the produced fip to fail to boot.
	# see https://github.com/repk/gxlimg/issues/19
	# run_host_command_logged gxlimg -t bl3x -s raw-u-boot.bin "${EXTRACT_DIR}/bl33.enc"
	run_host_x86_binary_logged "$AML_ENCRYPT" --bl3sig \
		--input raw-u-boot.bin \
		--output "${EXTRACT_DIR}/bl33.enc" \
		--level v3 --type bl33
	run_host_command_logged gxlimg \
		-t fip \
		--bl2 "${EXTRACT_DIR}/bl2.sign" \
		--ddrfw "${EXTRACT_DIR}/ddr4_1d.fw" \
		--ddrfw "${EXTRACT_DIR}/ddr4_2d.fw" \
		--ddrfw "${EXTRACT_DIR}/ddr3_1d.fw" \
		--ddrfw "${EXTRACT_DIR}/piei.fw" \
		--ddrfw "${EXTRACT_DIR}/lpddr4_1d.fw" \
		--ddrfw "${EXTRACT_DIR}/lpddr4_2d.fw" \
		--ddrfw "${EXTRACT_DIR}/diag_lpddr4.fw" \
		--ddrfw "${EXTRACT_DIR}/aml_ddr.fw" \
		--ddrfw "${EXTRACT_DIR}/lpddr3_1d.fw" \
		--bl30 "${EXTRACT_DIR}/bl30.enc" \
		--bl31 "${EXTRACT_DIR}/bl31.enc" \
		--bl33 "${EXTRACT_DIR}/bl33.enc" \
		--rev v3 u-boot.bin

	if [ ! -s u-boot.bin ]; then
		display_alert "${BOARD}" "FIP repack produced empty u-boot.bin" "err"
		exit 1
	fi
}

function post_family_tweaks_bsp__cainiao-cniot-core() {
	display_alert "${BOARD}" "Installing ALSA UCM configuration files" "info"

	# Use ALSA UCM via GUI: Install a desktop environment such as GNOME, PipeWire, and WirePlumber.

	# Use ALSA UCM via CLI: alsactl init && alsaucm set _verb "HiFi" set _enadev "HDMI" set _enadev "Speaker"
	# playback via HDMI: aplay -D plughw:cainiaocniotcor,0 /usr/share/sounds/alsa/Front_Center.wav
	# playback via internal speaker: aplay -D plughw:cainiaocniotcor,1 /usr/share/sounds/alsa/Front_Center.wav

	install -Dm644 "${SRC}/packages/bsp/cainiao-cniot-core/cainiao-cniot-core-HiFi.conf" "${destination}/usr/share/alsa/ucm2/Amlogic/axg-sound-card/cainiao-cniot-core-HiFi.conf"
	install -Dm644 "${SRC}/packages/bsp/cainiao-cniot-core/cainiao-cniot-core.conf" "${destination}/usr/share/alsa/ucm2/Amlogic/axg-sound-card/cainiao-cniot-core.conf"

	if [ ! -d "${destination}/usr/share/alsa/ucm2/conf.d/axg-sound-card" ]; then
		mkdir -p "${destination}/usr/share/alsa/ucm2/conf.d/axg-sound-card"
	fi
	ln -sfv /usr/share/alsa/ucm2/Amlogic/axg-sound-card/cainiao-cniot-core.conf \
		"${destination}/usr/share/alsa/ucm2/conf.d/axg-sound-card/cainiao-cniot-core.conf"
}
