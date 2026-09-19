# Phytium E2000Q quad core 2/4GB RAM 2x GBE USB3 HDMI WiFi/BT mini-PCIe
BOARD_NAME="Phytium Pi"
BOARD_VENDOR="phytium"
BOARDFAMILY="phytium-embedded"
BOARD_MAINTAINER="chainsx"
INTRODUCED="2023"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
BOOT_FDT_FILE="phytium/phytiumpi_firefly.dtb"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyAMA1,115200 earlycon=pl011,0x2800d000 rootfstype=ext4 rootwait cma=256m"
declare -g ATF_SKIP_LDFLAGS_WL="yes"

function post_family_tweaks__phytiumpi() {
	display_alert "Applying bt blobs"
	cp -v "$SRC/packages/blobs/phytiumpi/rtlbt/systemd-hciattach.service" "$SDCARD/etc/systemd/system/systemd-hciattach.service"
	cp -v "$SRC/packages/blobs/phytiumpi/rtlbt/rtk_hciattach" "$SDCARD/usr/bin/rtk_hciattach"
	cp -v "$SRC/packages/blobs/phytiumpi/rtlbt/rtl8821c_config" "$SDCARD/lib/firmware/rtlbt/rtl8821c_config"
	cp -v "$SRC/packages/blobs/phytiumpi/rtlbt/rtl8821c_fw" "$SDCARD/lib/firmware/rtlbt/rtl8821c_fw"
}
