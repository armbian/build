# Rockchip RK3528A quad core 1GB RAM SoC dual GBe eMMC USB2 USB-C WiFi6 BT5.3
BOARD_NAME="NanoPi R28S"
BOARD_VENDOR="friendlyelec"
BOARDFAMILY="rk35xx"
BOOTCONFIG="hinlink_rk3528_defconfig"
BOARD_MAINTAINER=""
INTRODUCED="2026"
KERNEL_TARGET="vendor"
FULL_DESKTOP="no"
HAS_VIDEO_OUTPUT="no"
BOOT_FDT_FILE="rockchip/rk3528-nanopi-rev03.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOOTFS_TYPE="ext4"
BOOTSIZE="512"

function post_family_tweaks_bsp__nanopi_r28s_net_led() {
	install -m 644 $SRC/packages/bsp/nanopi-r28s/nanopi-r28s-net-led.service $destination/etc/systemd/system/
}

function post_family_tweaks__nanopi_r28s_enable_net_led() {
	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable nanopi-r28s-net-led.service >/dev/null 2>&1"
}
