# Allwinner A733 octa core 2-16GB RAM GBE USB3 WiFi/BT NVMe eMMC
BOARD_NAME="Orange Pi 4 Pro"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun60iw2"
BOARD_MAINTAINER="shkolnik"
INTRODUCED="2025"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
IMAGE_PARTITION_TABLE="msdos"

# --- Board-specific build configuration ---
BOOT_FDT_FILE="allwinner/sun60i-a733-orangepi-4-pro.dtb"
OVERLAY_PREFIX="sun60i-a733"
KERNELPATCHDIR="archive/sun60iw2-opi-vendor"

function write_uboot_platform() {
	local SCRIPT_DIR="$1"
	local DEVICE="$2"
	dd conv=notrunc,fsync status=none if="${SCRIPT_DIR}/boot0_sdcard.fex" of="${DEVICE}" bs=1k seek=8
	dd conv=notrunc,fsync status=none if="${SCRIPT_DIR}/boot_package.fex" of="${DEVICE}" bs=1k seek=16400
	sync "${DEVICE}"
}

function write_uboot_platform_mtd() {
	local SCRIPT_DIR="$1"   # dir holding boot0_spinor.fex + boot_package.fex
	flash_erase /dev/mtd0 0 0
	mtd_debug write /dev/mtd0 0      "$(stat -c%s "$SCRIPT_DIR/boot0_spinor.fex")" "$SCRIPT_DIR/boot0_spinor.fex"
	mtd_debug write /dev/mtd0 262144 "$(stat -c%s "$SCRIPT_DIR/boot_package.fex")" "$SCRIPT_DIR/boot_package.fex"
	sync
}

function post_family_tweaks__orangepi4pro() {
	display_alert "Orange Pi 4 Pro rootfs tweaks" "${BOARD}" "info"

	# Boot script loads uInitrd directly; minimal extraargs (headless server).
	echo "extraargs=coherent_pool=2M no_console_suspend fsck.fix=yes fsck.repair=yes" >> "${SDCARD}"/boot/armbianEnv.txt

	# Link AIC8800D80 WiFi/BT firmware blobs from armbian-firmware default
	# location to where the in-tree vendor driver expects them.
	if [[ -d "${SDCARD}/lib/firmware/aic8800/SDIO/aic8800D80" ]]; then
		ln -sfn aic8800/SDIO/aic8800D80 "${SDCARD}/lib/firmware/aic8800d80"
	else
		display_alert "aic8800D80 firmware not found in rootfs" "WiFi may not work; check armbian-firmware" "warn"
	fi

	# mtd-utils provides flash_erase/mtd_debug for MTD Flash > NVMe boot
	chroot_sdcard_apt_get_install mtd-utils
}
