# Allwinner R40 quad core 2Gb SoC Wifi eMMC
BOARD_NAME="Banana Pi M2 Ultra"
BOARDFAMILY="sun8i"
BOOTCONFIG="Bananapi_M2_Ultra_defconfig"
OVERLAY_PREFIX="sun8i-r40"
KERNEL_TARGET="current,edge"

function post_family_tweaks__fake_vcgencmd() {
    display_alert "$BOARD" "Installing fake vcgencmd" "info"
    # Never add this to Raspberry Pi board config files such as rpi4b.conf

	chroot $SDCARD /bin/bash -c "curl -o /usr/bin/vcgencmd \"https://raw.githubusercontent.com/clach04/fake_vcgencmd/0.0.2/vcgencmd\""
	chroot $SDCARD /bin/bash -c "chmod 755 /usr/bin/vcgencmd"
	chroot $SDCARD /bin/bash -c "mkdir -p /usr/share/doc/fake_vcgencmd"
	chroot $SDCARD /bin/bash -c "curl -o /usr/share/doc/fake_vcgencmd/LICENSE \"https://raw.githubusercontent.com/clach04/fake_vcgencmd/0.0.2/LICENSE\""
	chroot $SDCARD /bin/bash -c "curl -o /usr/share/doc/fake_vcgencmd/README.md \"https://raw.githubusercontent.com/clach04/fake_vcgencmd/0.0.2/README.md\""

	return 0
}
