case $BRANCH in
	default)
	BOOTSOURCE='https://github.com/helios-4/u-boot-marvell.git'
	BOOTBRANCH='branch:u-boot-2013.01-15t1-helios4'
	BOOTDIR='u-boot-armada'
	BOOTSCRIPT='boot-marvell.cmd:boot.cmd'

	UBOOT_TARGET_MAP="u-boot.mmc;;u-boot.mmc
		u-boot.flash;spi;u-boot.flash u-boot-uart.flash"

	UBOOT_USE_GCC='== 4.9'
	UBOOT_COMPILER='arm-linux-gnueabi-'

	BOOTPATCHDIR='u-boot-helios4'
	;;
	next)
	BOOTSOURCE='https://github.com/helios-4/u-boot.git'
	BOOTBRANCH='branch:helios4'
	BOOTDIR=$MAINLINE_UBOOT_DIR
	BOOTSCRIPT='boot-marvell.cmd:boot.cmd'

	UBOOT_TARGET_MAP=";;u-boot-spl.kwb:u-boot.mmc
		;spi;u-boot-spl.kwb:u-boot.flash"
	UBOOT_USE_GCC='> 7.0'

	OVERLAY_PREFIX='armada-388-helios4'

	BOOTPATCHDIR='u-boot-helios4-next'
	;;
esac


# Helios4 tweak
family_tweaks_s()
{
	# install fancontrol and mdadm
	chroot $SDCARD /bin/bash -c "apt-get -y -qq install fancontrol mdadm >/dev/null 2>&1"

	### Fancontrol tweaks

	# copy hwmon rules to fix device mapping
	cp $SRC/packages/bsp/helios4/90-helios4-hwmon.rules $SDCARD/etc/udev/rules.d/

	# copy fancontrol config
	case $BRANCH in
	default)
		cp $SRC/packages/bsp/helios4/fancontrol_pwm-fan-mvebu-default.conf $SDCARD/etc/fancontrol
		;;
	next)
		cp $SRC/packages/bsp/helios4/fancontrol_pwm-fan-mvebu-next.conf $SDCARD/etc/fancontrol
		;;
	esac

	### Mdadm tweaks

	# copy mdadm-fault-led script and set right permission
	cp $SRC/packages/bsp/helios4/mdadm-fault-led.sh $SDCARD/usr/sbin/
	chmod a+x $SDCARD/usr/sbin/mdadm-fault-led.sh

	# modify mdadm configuration
	echo -e "\n # Trigger Fault Led script when an event is detected" >> $SDCARD/etc/mdadm/mdadm.conf
	echo -e "PROGRAM /usr/sbin/mdadm-fault-led.sh" >> $SDCARD/etc/mdadm/mdadm.conf

	### Ethernet tweaks

	# copy and enable helios4-wol.service
	cp $SRC/packages/bsp/helios4/helios4-wol.service $SDCARD/usr/lib/systemd/system/
	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable helios4-wol.service >/dev/null 2>&1"
}
