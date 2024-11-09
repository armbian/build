# Allwinner H618 quad core 1/2/4GB RAM SoC WiFi SPI USB-C
BOARD_NAME="BananaPi BPI-M4-Zero"
BOARDFAMILY="sun50iw9-bpi"
BOARD_MAINTAINER="pyavitz"
BOOTCONFIG="bananapi_m4zero_defconfig"
OVERLAY_PREFIX="sun50i-h616"
BOOT_FDT_FILE="allwinner/sun50i-h618-bananapi-m4-zero.dtb"
BOOT_LOGO="desktop"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
MODULES_BLACKLIST="rtw88_8821c rtw88_8821cu"
FORCE_BOOTSCRIPT_UPDATE="yes"
BOOTBRANCH_BOARD="tag:v2024.04"
BOOTPATCHDIR="v2024.04"
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"

function post_family_tweaks_bsp__bananapi_firmware() {
	if [[ -d "$SRC/packages/bsp/bananapi/brcm" ]] && [[ -d "$SRC/packages/bsp/bananapi/rtl_bt" ]]; then
		mkdir -p "${destination}"/lib/firmware/updates/brcm
		mkdir -p "${destination}"/lib/firmware/updates/rtl_bt
		display_alert "$BOARD" "Installing upstream firmware" "info"
		cp -fr $SRC/packages/bsp/bananapi/brcm/* "${destination}"/lib/firmware/updates/brcm/
		cp -fr $SRC/packages/bsp/bananapi/rtl_bt/* "${destination}"/lib/firmware/updates/rtl_bt/
	fi
}
