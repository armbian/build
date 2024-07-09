# Phytium PhytiumPi quad core 4GB SoC GBe USB3
BOARD_NAME="Phytium Pi"
BOARDFAMILY="phytium-embedded"
BOARD_MAINTAINER="chainsx"
KERNEL_TARGET="legacy,current"
BOOT_FDT_FILE="phytium/phytiumpi_firefly.dtb"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyAMA1,115200 earlycon=pl011,0x2800d000 rootfstype=ext4 rootwait cma=256m"

function post_family_tweaks__phytiumpi() {
	display_alert "Applying bt blobs"
	cp -v "$SRC/packages/blobs/phytiumpi/rtlbt/systemd-hciattach.service" "$SDCARD/etc/systemd/system/systemd-hciattach.service"
	cp -v "$SRC/packages/blobs/phytiumpi/rtlbt/rtk_hciattach" "$SDCARD/usr/bin/rtk_hciattach"
	cp -v "$SRC/packages/blobs/phytiumpi/rtlbt/rtl8821c_config" "$SDCARD/lib/firmware/rtlbt/rtl8821c_config"
	cp -v "$SRC/packages/blobs/phytiumpi/rtlbt/rtl8821c_fw" "$SDCARD/lib/firmware/rtlbt/rtl8821c_fw"
}
