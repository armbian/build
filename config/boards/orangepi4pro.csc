# Allwinner A733 octa core 2-16GB RAM GBE USB3 WiFi/BT NVMe eMMC
BOARD_NAME="Orange Pi 4 Pro"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun60iw2"
BOARD_MAINTAINER="shkolnik"
INTRODUCED="2025"
KERNEL_TARGET="vendor,edge"
KERNEL_TEST_TARGET="vendor,edge"
IMAGE_PARTITION_TABLE="msdos"
HAS_VIDEO_OUTPUT="no" # no desktop on this vendor kernel; board-level so the build-list inventory sees it

BOOTCONFIG_VENDOR="sun60iw2p1_t736_defconfig"
BOOTCONFIG_EDGE="orangepi_4_pro_defconfig"

BOOT_FDT_FILE="allwinner/sun60i-a733-orangepi-4-pro.dtb"
SUNXI_BOOT0_SDCARD_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_sdcard_orangepi4pro.fex"
SUNXI_BOOT0_SPINOR_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_spinor_orangepi4pro.fex"
SUNXI_SYS_CONFIG_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/sys_config_orangepi.fex"

# Packages needed for hardware enablement and flashing
PACKAGE_LIST_BOARD="mtd-utils rfkill bluetooth bluez bluez-tools"

# AIC8800
AIC8800_TYPE="sdio"
enable_extension "radxa-aic8800"

# AIC8800 Wireless
function post_family_tweaks_bsp__aic8800_wireless() {
	display_alert "$BOARD" "Installing AIC8800 Tweaks" "info"
	mkdir -p "${destination}"/etc/modprobe.d
	mkdir -p "${destination}"/etc/modules-load.d
	# Add wireless conf
	cat > "${destination}"/etc/modprobe.d/aic8800-orangepi4pro.conf <<- EOT
		options aic8800_fdrv_sdio aicwf_dbg_level=0 custregd=0 ps_on=0
		options aic8800_bsp aic_fw_path=/lib/firmware/aic8800/SDIO/aic8800D80
	EOT
	# Add needed bluetooth modules
	cat > "${destination}"/etc/modules-load.d/aic8800-btlpm.conf <<- EOT
		hidp
		rfcomm
		bnep
		aic8800_btlpm_sdio
	EOT
	# Add AIC8800 Bluetooth Service and Script
	if [[ -d "$SRC/packages/bsp/aic8800" ]]; then
		install -d -m 0755 "${destination}/usr/bin"
		install -m 0755 "$SRC/packages/bsp/aic8800/aic-bluetooth" "${destination}/usr/bin/aic-bluetooth"
		install -d -m 0755 "${destination}/usr/lib/systemd/system"
		install -m 0644 "$SRC/packages/bsp/aic8800/aic-bluetooth.service" "${destination}/usr/lib/systemd/system/aic-bluetooth.service"
	fi
}

function post_family_tweaks__enable_aic8800_bluetooth_service() {
	display_alert "$BOARD" "Enabling AIC8800 Bluetooth Service" "info"
	if chroot_sdcard test -f /usr/lib/systemd/system/aic-bluetooth.service || chroot_sdcard test -f /lib/systemd/system/aic-bluetooth.service || chroot_sdcard test -f /etc/systemd/system/aic-bluetooth.service; then
		chroot_sdcard systemctl --no-reload enable aic-bluetooth.service
	fi
}

# Invalidate U-Boot cache if any of the blobs change
UBOOT_HASH_EXTRA="$(cat "${SUNXI_BOOT0_SDCARD_FEX}" "${SUNXI_BOOT0_SPINOR_FEX}" "${SUNXI_SYS_CONFIG_FEX}" | sha256sum | cut -d' ' -f1)"

# The 4 Pro has 16 MB SPI-NOR; support writing the bootloader to MTD
function write_uboot_platform_mtd() {
	local SCRIPT_DIR="$1"
	[[ -f "${SCRIPT_DIR}/boot0_spinor.fex" ]] || SCRIPT_DIR="/usr/lib/linux-u-boot-edge-orangepi4pro"
	[[ -f "${SCRIPT_DIR}/boot0_spinor.fex" ]] || SCRIPT_DIR="${DIR}"
	local TARGET_DEV="${2:-/dev/mtd0}"
	# Ensure character MTD device (/dev/mtd0) even if block device (/dev/mtdblock0) was passed
	local MTD_DEV="${TARGET_DEV/mtdblock/mtd}"
	[[ -c "${MTD_DEV}" ]] || MTD_DEV="/dev/mtd0"
	[[ -c "${MTD_DEV}" ]] || { echo "write_uboot_platform_mtd: MTD device ${MTD_DEV} not found" >&2; return 1; }

	local BOOT0="${SCRIPT_DIR}/boot0_spinor.fex"
	local BOOTPKG="${SCRIPT_DIR}/boot_package.fex"

	[[ -f "${BOOT0}" ]] || { echo "write_uboot_platform_mtd: ${BOOT0} not found" >&2; return 1; }
	[[ -f "${BOOTPKG}" ]] || { echo "write_uboot_platform_mtd: ${BOOTPKG} not found" >&2; return 1; }

	local SIZE_BOOT0; SIZE_BOOT0="$(stat -c%s "${BOOT0}")"
	local SIZE_BOOTPKG; SIZE_BOOTPKG="$(stat -c%s "${BOOTPKG}")"

	echo "Erasing MTD device ${MTD_DEV} (4MB for bootloader)..."
	flash_erase "${MTD_DEV}" 0 1024 || { echo "write_uboot_platform_mtd: flash_erase failed on ${MTD_DEV}" >&2; return 1; }

	echo "Writing ${BOOT0} (${SIZE_BOOT0} bytes) to ${MTD_DEV} @ 0..."
	mtd_debug write "${MTD_DEV}" 0 "${SIZE_BOOT0}" "${BOOT0}" ||
		{ echo "write_uboot_platform_mtd: writing ${BOOT0} failed" >&2; return 1; }

	echo "Writing ${BOOTPKG} (${SIZE_BOOTPKG} bytes) to ${MTD_DEV} @ 262144 (256KB)..."
	mtd_debug write "${MTD_DEV}" 262144 "${SIZE_BOOTPKG}" "${BOOTPKG}" ||
		{ echo "write_uboot_platform_mtd: writing ${BOOTPKG} failed" >&2; return 1; }

	sync
	echo "write_uboot_platform_mtd: successfully flashed SPI NOR bootloader to ${MTD_DEV}"
	return 0
}

