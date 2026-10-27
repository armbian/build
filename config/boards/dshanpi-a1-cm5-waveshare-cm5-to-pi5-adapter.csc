# Rockchip RK3576 octa core 4-16GB RAM eMMC GbE WiFi/BT
BOARD_NAME="100ASK DshanPi A1 CM5 on Waveshare CM5-to-Pi5-Adapter"
BOARDFAMILY="rk35xx"
BOOT_SOC="rk3576"
BOARD_MAINTAINER="sckiyo"
BOARD_VENDOR="dongshanpi"
INTRODUCED="2026"
BOOTCONFIG="dshanpi-a1-cm5-rk3576_defconfig"
BOOT_SCENARIO="spl-blobs"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3576-dshanpi-a1-cm5-waveshare-cm5-to-pi5-adapter.dtb"
IMAGE_PARTITION_TABLE="gpt"

# AIC8800D80 is SDIO Wi-Fi and UART7 Bluetooth.
# UART7 is serial7, so the device is /dev/ttyS7.
# The stock aic-bluetooth script hardcodes /dev/ttyS1.
DSHANPI_AIC8800_WIFI_ENABLE="${DSHANPI_AIC8800_WIFI_ENABLE:-yes}"
DSHANPI_AIC8800_BT_UART="${DSHANPI_AIC8800_BT_UART:-/dev/ttyS7}"

if [[ "${DSHANPI_AIC8800_WIFI_ENABLE}" == "yes" ]]; then
	enable_extension "radxa-aic8800"
	AIC8800_TYPE="sdio"
	PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"
fi

function post_family_tweaks_bsp__dshanpi_a1_cm5_aic8800() {
	[[ "${DSHANPI_AIC8800_WIFI_ENABLE}" == "yes" ]] || return 0

	display_alert "$BOARD" "Installing AIC8800 tweaks" "info"
	mkdir -p "${destination}/etc/modprobe.d"
	cat > "${destination}/etc/modprobe.d/aic8800-wireless.conf" <<- EOT
		options aic8800_fdrv_sdio aicwf_dbg_level=0 custregd=0 ps_on=0
	EOT

	mkdir -p "${destination}/etc/modules-load.d"
	cat > "${destination}/etc/modules-load.d/aic8800-btlpm.conf" <<- EOT
		hidp
		rfcomm
		bnep
		aic8800_btlpm_sdio
	EOT

	if [[ ! -d "$SRC/packages/bsp/aic8800" ]]; then
		display_alert "$BOARD" "Skipping AIC8800 BT assets" "warn"
		return 0
	fi

	install -d -m 0755 "${destination}/usr/bin"
	install -m 0755 "$SRC/packages/bsp/aic8800/aic-bluetooth" "${destination}/usr/bin/aic-bluetooth"
	sed -i "s|/dev/ttyS1|${DSHANPI_AIC8800_BT_UART}|g" "${destination}/usr/bin/aic-bluetooth"
	install -d -m 0755 "${destination}/usr/lib/systemd/system"
	install -m 0644 "$SRC/packages/bsp/aic8800/aic-bluetooth.service" "${destination}/usr/lib/systemd/system/aic-bluetooth.service"
}

function post_family_tweaks__dshanpi_a1_cm5_enable_aic8800_bt() {
	[[ "${DSHANPI_AIC8800_WIFI_ENABLE}" == "yes" ]] || return 0

	display_alert "$BOARD" "Enabling AIC8800 Bluetooth service" "info"
	if chroot_sdcard test -f /usr/lib/systemd/system/aic-bluetooth.service \
		|| chroot_sdcard test -f /lib/systemd/system/aic-bluetooth.service \
		|| chroot_sdcard test -f /etc/systemd/system/aic-bluetooth.service; then
		chroot_sdcard systemctl --no-reload enable aic-bluetooth.service
	else
		display_alert "$BOARD" "aic-bluetooth.service not found" "warn"
	fi
}

# RK3576 TF boot needs the FlashBoost blob in idbloader.img.
# Binman images omit FlashBoost.
# boot_merger in uboot_custom_postprocess adds FlashBoost.
function post_family_config__dshanpi_a1_cm5_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	BOOT_SCENARIO="tpl-blob-atf-mainline"
	prepare_boot_configuration

	declare -g ATFBRANCH="tag:v2.15.0"
	declare -g ATFPATCHDIR="atf-rockchip64/v2.15"

	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.10"
	declare -g BOOTPATCHDIR="v2026.10"
	declare -g BOOTDIR="u-boot-dshanpi-a1-cm5"

	# Make needs the DDR blob to build idbloader.img. boot_merger then replaces that file.
	declare -g UBOOT_TARGET_MAP="BL31=bl31.elf ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;idbloader.img u-boot.itb"

	# The family write_uboot_platform prefers u-boot-rockchip.bin when that file exists.
	# u-boot-rockchip.bin has no FlashBoost. Write idbloader.img and u-boot.itb instead.
	unset write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/idbloader.img" "of=$2" seek=64 conv=notrunc status=none
		dd "if=$1/u-boot.itb" "of=$2" seek=16384 conv=notrunc status=none
	}
}
