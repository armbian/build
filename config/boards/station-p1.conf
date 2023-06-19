# Rockchip RK3399 hexa core 4GB LPDDR4 SoC eMMC GBE USB3
BOARD_NAME="Station P1"
BOARDFAMILY="media"
BOARD_MAINTAINER="150balbes"
BOOTCONFIG="roc-pc-plus-rk3399_defconfig"
KERNEL_TARGET="legacy,current,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-roc-pc-plus.dtb"
BOOT_SUPPORT_SPI=yes
BOOT_SCENARIO="tpl-spl-blob"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS2,1500000 console=tty0"
ASOUND_STATE="asound.state.station-p1"

function post_family_tweaks__station_p1() {
    display_alert "$BOARD" "Installing board tweaks" "info"

	cp -R $SRC/packages/blobs/rtl8723bt_fw/* $SDCARD/lib/firmware/rtl_bt/
	cp -R $SRC/packages/blobs/station/firmware/* $SDCARD/lib/firmware/

	return 0
}
