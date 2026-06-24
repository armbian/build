# Allwinner A733 (sun60iw2) octa-core 1-16GB, WiFi6/BT (USB), NPU, GPU, UFS, no Ethernet
BOARD_NAME="Radxa Cubie A7Z"
BOARD_VENDOR="radxa"
BOARDFAMILY="sun60iw2"
BOARD_MAINTAINER="shkolnik"
INTRODUCED="2025"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
IMAGE_PARTITION_TABLE="msdos"

# --- Board-specific build configuration ---
BOOT_FDT_FILE="allwinner/sun60i-a733-cubie-a7z.dtb"
OVERLAY_PREFIX="sun60i-a733"
KERNELPATCHDIR="archive/sun60iw2-cubie-vendor"

# WiFi/BT = FCU760K (AIC8800D80 over USB)
# Override MODULES with the bus-suffixed USB modules (aic8800-usb-dkms) so only those load.
MODULES="aic_load_fw_usb aic8800_fdrv_usb aic_btusb_usb"
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"
AIC8800_TYPE="usb"
enable_extension "radxa-aic8800"

function write_uboot_platform() {
	local SCRIPT_DIR="$1" DEVICE="$2"
	dd conv=notrunc,fsync status=none if="${SCRIPT_DIR}/boot0_sdcard.fex" of="${DEVICE}" bs=1k seek=128
	dd conv=notrunc,fsync status=none if="${SCRIPT_DIR}/boot_package.fex" of="${DEVICE}" bs=1k seek=12288
	sync "${DEVICE}"
}

# Fetch the Cubie's DRAM blobs and point the family's SUNXI_*_FEX vars at them.
function fetch_custom_uboot__cubiea7z() {
	local work_dir="$(mktemp -d)"

	# A733 SD path uses one boot0; reuse it for the spinor slot (SPI untested).
	declare -g SUNXI_SYS_CONFIG_FEX="${work_dir}/sys_config.fex"
	declare -g SUNXI_BOOT0_SDCARD_FEX="${work_dir}/boot0_stock.bin"
	declare -g SUNXI_BOOT0_SPINOR_FEX="${work_dir}/boot0_stock.bin"

	# Board sys_config (correct 1800 MT/s DRAM): single file from Radxa
	# allwinner-device, fetched directly over HTTPS.
	local CUBIE_DEVICE_REPO="https://raw.githubusercontent.com/radxa/allwinner-device"
	local CUBIE_DEVICE_REF="79d54f44e14111db3845096cef0639a6c9222707"   # device-a733-v1.46
	display_alert "Cubie A7Z: fetching board sys_config" "${CUBIE_DEVICE_REF:0:12}" "info"
	run_host_command_logged wget -q -O "${SUNXI_SYS_CONFIG_FEX}" "${CUBIE_DEVICE_REPO}/${CUBIE_DEVICE_REF}/configs/cubie_a7z/sys_config.fex"

	# Radxa doesn't publish a boot0 blob, but we can extract it from their official
	# image (known-good LPDDR4X init).
	local CUBIE_IMAGE_URL="https://github.com/radxa-build/radxa-cubie-a7z/releases/download/rsdk-b1/radxa-cubie-a7z_bullseye_kde_b1.output_512.img.xz"
	local CUBIE_IMAGE_BOOT0_SECTOR="256"
	local CUBIE_IMAGE_BOOT0_SIZE="262144"
	local CUBIE_IMAGE_BOOT0_SHA256="ec93227f0ca2fc09a18ee92fbdab7b7a81e2effb824937bf20652d9c9cf4e69e"
	display_alert "Cubie A7Z: downloading Radxa release image and extracting stock boot0" "${CUBIE_IMAGE_URL##*/}" "info"
	wget -qO- "${CUBIE_IMAGE_URL}" | unxz -c | dd of="${SUNXI_BOOT0_SDCARD_FEX}" bs=512 skip="${CUBIE_IMAGE_BOOT0_SECTOR}" count="$(( CUBIE_IMAGE_BOOT0_SIZE / 512 ))" iflag=fullblock status=none || true
	echo "${CUBIE_IMAGE_BOOT0_SHA256}  ${SUNXI_BOOT0_SDCARD_FEX}" | sha256sum -c - || exit_with_error "Cubie A7Z: extracted boot0 SHA256 mismatch"
}
