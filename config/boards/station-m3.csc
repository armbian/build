# Rockchip RK3588s 2GB-16GB GBE eMMC NVMe SATA USB3 WiFi
BOARD_NAME="Station M3"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="chainsx"
KERNEL_TARGET="legacy,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-roc-pc.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS02,1500000 console=tty0"
BOOT_SOC="rk3588"
IMAGE_PARTITION_TABLE="gpt"
declare -g UEFI_EDK2_BOARD_ID="station-m3" # This _only_ used for uefi-edk2-rk3588 extension

function post_family_tweaks__station_m3() {
    display_alert "$BOARD" "Installing board tweaks" "info"

	cp -R $SRC/packages/blobs/rtl8723bt_fw/* $SDCARD/lib/firmware/rtl_bt/
	cp -R $SRC/packages/blobs/station/firmware/* $SDCARD/lib/firmware/
	return 0
}

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__stationm3_use_vendor_uboot() {
	BOOTCONFIG="rk3588_defconfig"
	BOOTSOURCE='https://github.com/150balbes/u-boot-rk'
	BOOTBRANCH='branch:rk3588'
	BOOTDIR="u-boot-${BOARD}"
	BOOTPATCHDIR="u-boot-station-p2"
}
