# RK3399 hexa core 4GB SoC 2.5GbE eMMC USB3 SATA M.2 UPS
BOARD_NAME="Helios64"
BOARDFAMILY="rockchip64" # Used to be rk3399
BOARD_MAINTAINER=""
BOOTCONFIG="helios64-rk3399_defconfig"
BOOT_SCENARIO="blobless"
KERNEL_TARGET="current,edge"
MODULES="lm75 ledtrig-netdev"
MODULES_LEGACY="lm75"
FULL_DESKTOP="yes"
PACKAGE_LIST_BOARD="mdadm i2c-tools fancontrol"
PACKAGE_LIST_BOARD_REMOVE="fake-hwclock"
CPUMAX="1800000"

function post_family_tweaks__helios64_enable_heartbeat() {
	display_alert "$BOARD" "Installing board tweaks" "info"

	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable helios64-heartbeat-led.service >/dev/null 2>&1"

	return 0
}

function post_family_tweaks_bsp__helios64() {
	display_alert "Installing BSP firmware and fixups"

	mkdir -p $destination/etc/udev/rules.d/
	mkdir -p $destination/etc/systemd/system/fancontrol.service.d/
	mkdir -p $destination/lib/systemd/system/
	mkdir -p $destination/lib/systemd/system-shutdown/
	cp $SRC/packages/bsp/helios64/50-usb-realtek-net.rules $destination/etc/udev/rules.d/
	cp $SRC/packages/bsp/helios64/70-keep-usb-lan-as-eth1.rules $destination/etc/udev/rules.d/
	cp $SRC/packages/bsp/helios64/90-helios64-ups.rules $destination/etc/udev/rules.d/
	cp $SRC/packages/bsp/helios64/asound.conf $destination/etc/
	install -m 755 $SRC/packages/bsp/helios64/disable_auto_poweron $destination/lib/systemd/system-shutdown/

	### Fancontrol tweaks
	# copy hwmon rules to fix device mapping
	# changed to only use one file regardless of branch
	install -m 644 $SRC/packages/bsp/helios64/90-helios64-hwmon.rules $destination/etc/udev/rules.d/

	install -m 644 $SRC/packages/bsp/helios64/fancontrol.service.pid-override $destination/etc/systemd/system/fancontrol.service.d/pid.conf

	# copy fancontrol config
	install -m 644 $SRC/packages/bsp/helios64/fancontrol.conf $destination/etc/fancontrol

	# LED tweak
	if [[ $BRANCH == legacy ]]; then
		install -m 644 $SRC/packages/bsp/helios64/helios64-heartbeat-led-legacy.service $destination/etc/systemd/system/helios64-heartbeat-led.service
	else
		install -m 644 $SRC/packages/bsp/helios64/helios64-heartbeat-led.service $destination/etc/systemd/system/
	fi

	# UPS service
	cp $SRC/packages/bsp/helios64/helios64-ups.service $destination/lib/systemd/system/
	cp $SRC/packages/bsp/helios64/helios64-ups.timer $destination/lib/systemd/system/
	install -m 755 $SRC/packages/bsp/helios64/helios64-ups.sh $destination/usr/bin/helios64-ups.sh

	return 0
}
