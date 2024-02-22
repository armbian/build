# Rockchip RK3328 quad core 1GB-4GB GBE eMMC USB3 WiFi
BOARD_NAME="Station M1"
BOARDFAMILY="media"
BOARD_MAINTAINER="150balbes"
BOOTCONFIG="roc-pc-rk3328_defconfig"
KERNEL_TARGET="legacy,current,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3328-roc-pc.dtb"
SRC_EXTLINUX="yes"
SERIALCON="ttyS0,tty0"
SRC_CMDLINE="console=ttyS2,1500000 console=tty0"
ASOUND_STATE="asound.state.station-m1"

function post_family_tweaks__station_m1() {
    display_alert "$BOARD" "Installing board tweaks" "info"

	cp -R $SRC/packages/blobs/rtl8723bt_fw/* $SDCARD/lib/firmware/rtl_bt/
	cp -R $SRC/packages/blobs/station/firmware/* $SDCARD/lib/firmware/
	if [[ $BRANCH == legacy ]]; then
		install -m 755 $SRC/packages/bsp/rk3328/m1/rtk_hciattach $SDCARD/usr/bin/rtk_hciattach
		sed -e 's/exit 0//g' -i $SDCARD/etc/rc.local
		echo "su -c '/usr/bin/rtk_hciattach -n -s 115200 /dev/ttyS2 rtk_h5 &'" >> $SDCARD/etc/rc.local
		echo "exit 0" >> $SDCARD/etc/rc.local
	fi

	return 0
}
