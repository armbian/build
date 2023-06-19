# Rockchip RK3588s 2GB-16GB GBE eMMC NVMe SATA USB3 WiFi
BOARD_NAME="Station M3"
BOARDFAMILY="media"
BOARD_MAINTAINER="150balbes"
BOOTCONFIG="rk3588_defconfig"
KERNEL_TARGET="legacy"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-roc-pc.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS02,1500000 console=tty0"
IMAGE_PARTITION_TABLE="gpt"

function post_family_tweaks__station_m3() {
    display_alert "$BOARD" "Installing board tweaks" "info"

	cp -R $SRC/packages/blobs/rtl8723bt_fw/* $SDCARD/lib/firmware/rtl_bt/
	cp -R $SRC/packages/blobs/station/firmware/* $SDCARD/lib/firmware/
	if [[ $BRANCH == legacy ]]; then
		install -m 755 $SRC/packages/blobs/station/firefly_fan_control $SDCARD/usr/bin/firefly_fan_control
		install -m 755 $SRC/packages/blobs/station/firefly-fan-init $SDCARD/usr/bin/firefly-fan-init
		install -m 755 $SRC/packages/blobs/station/firefly-fan.service $SDCARD/usr/lib/systemd/system/firefly-fan.service
		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable firefly-fan.service >/dev/null 2>&1"
	fi

	return 0
}
