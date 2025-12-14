# Rockchip RK3566 quad core 1/2/4/8GB RAM WiFi/BT or GBE HDMI USB-C
BOARD_NAME="Radxa ZERO 3"
BOARD_VENDOR="radxa"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="radxa-zero3-rk3566_defconfig"
KERNEL_TARGET="vendor,current,edge"
KERNEL_TEST_TARGET="vendor,current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3566-radxa-zero3.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"

PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"
# add for OBEX file transfer:
# PACKAGE_LIST_BOARD+=" bluez-obexd"
AIC8800_TYPE="sdio"
enable_extension "radxa-aic8800"

function post_family_config__use_mainline_uboot() {

	# boot.scr will use whatever u-boot detects and sets 'fdtfile' to.
	# This however this doesn't work with Rockchip bsp based kernels since naming differs.
	# So leave decision to u-boot ONLY when mainline kernel is used.
	if [[ "${BRANCH}" != "vendor" ]]; then
		unset BOOT_FDT_FILE
	fi

	BOOTCONFIG="radxa-zero-3-rk3566_defconfig"
	BOOTSOURCE="https://github.com/u-boot/u-boot"
	BOOTBRANCH="tag:v2025.10"
	BOOTPATCHDIR="v2025.10"

	UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"
	## For binman-atf-mainline: setting BOOT_SCENARIO at the top would break branch=vendor, so we don't enable it globally.
	# We cannot set BOOT_SOC=rk3566 due to side effects in Armbian scripts; ATF_TARGET_MAP is the safer override.
	# ATF does not currently separate rk3566 from rk3568.
	#ATF_TARGET_MAP="M0_CROSS_COMPILE=arm-linux-gnueabi- PLAT=rk3568 bl31;;build/rk3568/release/bl31/bl31.elf:bl31.elf"
	#UBOOT_TARGET_MAP="BL31=bl31.elf ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}

function post_family_tweaks_bsp__aic8800_wireless() {
	display_alert "$BOARD" "Installing AIC8800 Tweaks" "info"
	mkdir -p "${destination}"/etc/modprobe.d
	mkdir -p "${destination}"/etc/modules-load.d
	# Add wireless conf
	cat > "${destination}"/etc/modprobe.d/aic8800-wireless.conf <<- EOT
	options aic8800_fdrv_sdio aicwf_dbg_level=0 custregd=0 ps_on=0
	#options aic8800_bsp_sdio aic_fw_path=/lib/firmware/aic8800_fw/SDIO/aic8800
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
	else
		display_alert "$BOARD" "Skipping AIC8800 BT assets (packages/bsp/aic8800 not found)" "warn"
	fi
}

# Enable AIC8800 Bluetooth Service
function post_family_tweaks__enable_aic8800_bluetooth_service() {
	display_alert "$BOARD" "Enabling AIC8800 Bluetooth Service" "info"
	if chroot_sdcard test -f /lib/systemd/system/aic-bluetooth.service || chroot_sdcard test -f /etc/systemd/system/aic-bluetooth.service; then
		chroot_sdcard systemctl --no-reload enable aic-bluetooth.service
	else
		display_alert "$BOARD" "aic-bluetooth.service not found in image; skipping enable" "warn"
	fi
}