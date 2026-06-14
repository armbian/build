# Allwinner A733 octa core 2-16GB RAM GBE USB3 WiFi/BT NVMe eMMC
BOARD_NAME="Orange Pi 4 Pro"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun60iw2"
BOARD_MAINTAINER="shkolnik"
INTRODUCED="2025"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
IMAGE_PARTITION_TABLE="msdos"

# Video output DOES work without GPU acceleration but we still don't want to
# build desktop targets.
HAS_VIDEO_OUTPUT="no"
FULL_DESKTOP="no"

# --- Board-specific kernel bits (source/branch/defconfig come from the family) ---
# Device tree + this board's patch set. The DRAM blobs (boot0 + sys_config) use
# the family defaults (orangepi-build's a733 blobs, correct for this board's
# LPDDR5), so the SUNXI_*_FEX path vars are left unset here.
BOOT_FDT_FILE="allwinner/sun60i-a733-orangepi-4-pro.dtb"
OVERLAY_PREFIX="sun60i-a733"
KERNELPATCHDIR="archive/sun60iw2-opi-vendor"

# NOTE: Don't swap in an out-of-tree AIC8800 DKMS driver — it shadows the
# in-tree bsp symbols and breaks fdrv ("Unknown symbol").
MODULES="aic8800_bsp aic8800_fdrv aic8800_btlpm"

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
