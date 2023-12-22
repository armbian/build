# Allwinner H3 quad core 512MB/1GB RAM SoC headless 1xGBE 1xETH eMMC WiFi/BT
BOARD_NAME="NanoPi R1"
BOARDFAMILY="sun8i"
BOARD_MAINTAINER=""
BOOTCONFIG="nanopi_r1_defconfig"
MODULES="g_serial"
MODULES_BLACKLIST="lima"
DEFAULT_OVERLAYS="usbhost0 usbhost1 uart1"
DEFAULT_CONSOLE="serial"
SERIALCON="ttyS1,ttyGS0"
HAS_VIDEO_OUTPUT="no"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"
BOOT_FDT_FILE="sun8i-h3-nanopi-r1.dtb"

function post_family_tweaks__nanopi_r1_related_configs() {
	# rename eth1 to wan0
	echo 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*",ATTR{address}=="00:00:00:00:00:00",ATTR{dev_id}=="0x0", ATTR{type}=="1",KERNEL=="eth1", NAME="wan0"' > $SDCARD/etc/udev/rules.d/70-persisetn-net.rules
	# change default console to tty1 which is wired to the chasis
	sed -i "s/ttyS0/ttyS1/" $SDCARD/boot/boot.cmd
	mkimage -C none -A arm -T script -d $SDCARD/boot/boot.cmd $SDCARD/boot/boot.scr
}
