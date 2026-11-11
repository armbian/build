# Allwinner A733 octa-core 2-16GB LPDDR5 WiFi6/BT GBE USB3 NVMe soldered eMMC
BOARD_NAME="Sige6"
BOARD_VENDOR="armsom"
BOARDFAMILY="sun60iw2"
BOARD_MAINTAINER=""
INTRODUCED="2026"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
IMAGE_PARTITION_TABLE="msdos"

BOOT_FDT_FILE="allwinner/sun60i-a733-armsom-sige6.dtb"

# AIC8800D80 combo: BT is UART HCI on ttyS1 and needs userspace bring-up
SUN60IW2_UART_BT="yes"

# Supply Sige6 LPDDR5 boot files to uboot_custom_postprocess.
# Source: ArmSoM T527_AIOT_V1.4.8, commit 9826635829d0.
# boot0: DRAM V0.601, packed with sys_config and update_chip.
SUNXI_BOOT0_SDCARD_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_sdcard_armsom-sige6.fex"
SUNXI_BOOT0_SPINOR_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_spinor_armsom-sige6.fex"
SUNXI_SYS_CONFIG_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/sys_config_armsom-sige6.fex"

# Invalidate U-Boot cache if any of the blobs change
UBOOT_HASH_EXTRA="$(cat "${SUNXI_BOOT0_SDCARD_FEX}" "${SUNXI_BOOT0_SPINOR_FEX}" "${SUNXI_SYS_CONFIG_FEX}" | sha256sum | cut -d' ' -f1)"

# Install U-Boot to SPI-NOR using the Orange Pi 4 Pro layout.
function write_uboot_platform_mtd() {
	local SCRIPT_DIR="$1"
	[[ -f "${SCRIPT_DIR}/boot0_spinor.fex" ]] || { echo "write_uboot_platform_mtd: missing ${SCRIPT_DIR}/boot0_spinor.fex" >&2; return 1; }
	[[ -f "${SCRIPT_DIR}/boot_package.fex" ]] || { echo "write_uboot_platform_mtd: missing ${SCRIPT_DIR}/boot_package.fex" >&2; return 1; }
	flash_erase /dev/mtd0 0 0 || return 1
	mtd_debug write /dev/mtd0 0 "$(stat -c%s "${SCRIPT_DIR}/boot0_spinor.fex")" "${SCRIPT_DIR}/boot0_spinor.fex" || return 1
	mtd_debug write /dev/mtd0 262144 "$(stat -c%s "${SCRIPT_DIR}/boot_package.fex")" "${SCRIPT_DIR}/boot_package.fex" || return 1
	sync
}
