# Allwinner A733 (sun60iw2) octa-core 1-16GB, WiFi6/BT (USB), NPU, GPU, UFS
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
BOOT0_OFFSET=128
BOOT_PACKAGE_OFFSET=12288

# WiFi/BT = FCU760K (AIC8800D80 over USB)
# Override MODULES with the bus-suffixed USB modules (aic8800-usb-dkms) so only those load.
MODULES="aic_load_fw_usb aic8800_fdrv_usb aic_btusb_usb"
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"
AIC8800_TYPE="usb"
enable_extension "radxa-aic8800"

# In-tree boot blobs consumed by the family's uboot_custom_postprocess.
# Extracted from Radxa's official OS image boot sector.
SUNXI_BOOT0_SDCARD_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_cubie-a7z.fex"
SUNXI_BOOT0_SPINOR_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_cubie-a7z.fex"
SUNXI_SYS_CONFIG_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/sys_config_cubie-a7z.fex"

# Invalidate U-Boot cache if any of the blobs change
UBOOT_HASH_EXTRA="$(cat "${SUNXI_BOOT0_SDCARD_FEX}" "${SUNXI_SYS_CONFIG_FEX}" | sha256sum | cut -d' ' -f1)"
