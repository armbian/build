# Allwinner H618 quad core 1/2/4GB RAM SoC WiFi SPI USB-C
BOARD_NAME="KickPi K2B"
BOARDFAMILY="sun50iw9-bpi"
BOARD_MAINTAINER="pyavitz"
BOOTCONFIG="kickpi_k2b_defconfig"
OVERLAY_PREFIX="sun50i-h616"
BOOT_FDT_FILE="sun50i-h618-kickpi-k2b.dtb"
BOOT_LOGO="desktop"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"
BOOTBRANCH_BOARD="tag:v2025.07"
BOOTPATCHDIR="v2025.07"
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"

# AIC8800
AIC8800_TYPE="sdio"
enable_extension "radxa-aic8800"

# AIC8800 Wireless
function post_family_tweaks_bsp__aic8800_wireless() {
	display_alert "$BOARD" "Installing AIC8800 Tweaks" "info"
	mkdir -p "${destination}"/etc/modprobe.d
	mkdir -p "${destination}"/etc/modules-load.d
	# Add wireless conf
	cat > "${destination}"/etc/modprobe.d/aic8800-wireless.conf <<- EOT
	options aic8800_fdrv_sdio aicwf_dbg_level=0 custregd=0 ps_on=0
	options aic8800_bsp_sdio aic_fw_path=/lib/firmware/aic8800_fw/SDIO/aic8800
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
		mkdir -p "${destination}"/etc/systemd/system
		mkdir -p "${destination}"/usr/bin
		cp -f "$SRC/packages/bsp/aic8800/aic-bluetooth" "${destination}"/usr/bin
		chmod +x "${destination}"/usr/bin/aic-bluetooth
		cp -f "$SRC/packages/bsp/aic8800/aic-bluetooth.service" "${destination}"/etc/systemd/system
	fi
}

# Enable AIC8800 Bluetooth Service
function post_family_tweaks__enable_aic8800_bluetooth_service() {
	display_alert "$BOARD" "Enabling AIC8800 Bluetooth Service" "info"
	chroot_sdcard systemctl --no-reload enable aic-bluetooth.service
}
