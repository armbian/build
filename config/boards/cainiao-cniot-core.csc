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
ASOUND_STATE="asound.state.khadas-vim3"

BOOTBRANCH_BOARD="tag:v2025.04"
BOOTPATCHDIR="v2025.04" # This has a patch that adds support for CAINIAO CNIoT-CORE.

UBOOT_TARGET_MAP="u-boot.bin"

function post_family_config__write_repacked_fip() {
	unset write_uboot_platform

	function write_uboot_platform() {
		dd if=$1/u-boot.bin of=$2 bs=512 seek=1 conv=fsync 2>&1
	}
}

function fetch_sources_tools__get_vendor_fip_and_gxlimg_source() {
	fetch_from_repo "https://github.com/retro98boy/cainiao-cniot-core-linux.git" "cainiao-cniot-core-linux" "branch:blobs"
	fetch_from_repo "https://github.com/repk/gxlimg.git" "gxlimg" "branch:master"
}

function build_host_tools__install_gxlimg() {
	# Compile and install only if git commit hash changed
	cd "${SRC}"/cache/sources/gxlimg || exit
	# need to check if /usr/local/bin/gxlimg to detect new Docker containers with old cached sources
	if [[ ! -f .commit_id || $(git rev-parse @ 2> /dev/null) != $(< .commit_id) || ! -f /usr/local/bin/gxlimg ]]; then
		display_alert "Compiling" "gxlimg" "info"
		run_host_command_logged make distclean
		run_host_command_logged make
		mkdir -p /usr/local/bin/
		cp gxlimg /usr/local/bin
		git rev-parse @ 2> /dev/null > .commit_id
	fi
}

function post_uboot_custom_postprocess__repack_vendor_fip_with_mainline_uboot() {
	display_alert "${BOARD}" "Repacking vendor FIP with mainline u-boot.bin" "info"

	BLOBS_DIR="$SRC"/cache/sources/cainiao-cniot-core-linux
	EXTRACT_DIR="$BLOBS_DIR"/extract

	rm -rf "$EXTRACT_DIR"
	mkdir "$EXTRACT_DIR"
	# gxlimg returns a non-zero value upon successful extraction, causing the Armbian build to fail. Adding "|| true" forces it to return zero.
	run_host_command_logged gxlimg -e "$BLOBS_DIR"/DDR.USB "$EXTRACT_DIR" || true

	mv u-boot.bin raw-u-boot.bin
	rm -f "$EXTRACT_DIR"/bl33.enc
	run_host_command_logged gxlimg -t bl3x -s raw-u-boot.bin "$EXTRACT_DIR"/bl33.enc
	run_host_command_logged gxlimg \
		-t fip \
		--bl2 "$EXTRACT_DIR"/bl2.sign \
		--ddrfw "$EXTRACT_DIR"/ddr4_1d.fw \
		--ddrfw "$EXTRACT_DIR"/ddr4_2d.fw \
		--ddrfw "$EXTRACT_DIR"/ddr3_1d.fw \
		--ddrfw "$EXTRACT_DIR"/piei.fw \
		--ddrfw "$EXTRACT_DIR"/lpddr4_1d.fw \
		--ddrfw "$EXTRACT_DIR"/lpddr4_2d.fw \
		--ddrfw "$EXTRACT_DIR"/diag_lpddr4.fw \
		--ddrfw "$EXTRACT_DIR"/aml_ddr.fw \
		--ddrfw "$EXTRACT_DIR"/lpddr3_1d.fw \
		--bl30 "$EXTRACT_DIR"/bl30.enc \
		--bl31 "$EXTRACT_DIR"/bl31.enc \
		--bl33 "$EXTRACT_DIR"/bl33.enc \
		--rev v3 u-boot.bin
}
