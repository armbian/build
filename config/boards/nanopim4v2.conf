# Rockchip RK3399 hexa core 4GB RAM SoC GBE eMMC USB3 USB-C WiFi/BT
BOARD_NAME="NanoPi M4V2"
BOARDFAMILY="rk3399"
BOOTCONFIG="nanopi-m4v2-rk3399_defconfig"
KERNEL_TARGET="legacy,current,edge"
FULL_DESKTOP="yes"
ASOUND_STATE="asound.state.rt5651"
BOOT_LOGO="desktop"

function post_family_tweaks__m4v2() {
    display_alert "$BOARD" "Installing board tweaks" "info"

	# enable fan support
	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable nanopim4-pwm-fan.service >/dev/null 2>&1"

	return 0
}
function post_family_tweaks_bsp__M4V2() {
    display_alert "Installing BSP firmware and fixups"

	# Bluetooth for most of others (custom patchram is needed only in legacy)
	install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
	cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	# Swap out the chip for some boards
	sed -i s%BCM4345C5%BCM4356A2%g $destination/lib/systemd/system/rk3399-bluetooth.service

	# Fan support
	cp $SRC/packages/bsp/nanopim4/nanopim4-pwm-fan.service $destination/lib/systemd/system/
	install -m 755 $SRC/packages/bsp/nanopim4/nanopim4-pwm-fan.sh $destination/usr/bin/nanopim4-pwm-fan.sh

	return 0
}

