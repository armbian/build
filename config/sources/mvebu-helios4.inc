case $BRANCH in
	default)
	BOOTSOURCE='https://github.com/helios-4/u-boot.git'
	BOOTBRANCH='branch:helios4'
	BOOTDIR=$MAINLINE_UBOOT_DIR
	BOOTSCRIPT='boot-marvell.cmd:boot.cmd'

	UBOOT_TARGET_MAP=";sdhc;u-boot-spl.kwb:u-boot.mmc
			  ;spi;u-boot-spl.kwb:u-boot.flash"

	UBOOT_USE_GCC='> 7.0'
	UBOOT_COMPILER='arm-linux-gnueabi-'
	OVERLAY_PREFIX='armada-388-helios4'

	BOOTPATCHDIR='u-boot-helios4'
	;;
	next|dev)
	OVERLAY_PREFIX='armada-388-helios4'
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

	cp $SRC/packages/bsp/helios4/fancontrol.service $SDCARD/etc/systemd/system/

	### Mdadm tweaks

	# copy mdadm-fault-led script and set right permission
	cp $SRC/packages/bsp/helios4/mdadm-fault-led.sh $SDCARD/usr/sbin/
	chmod a+x $SDCARD/usr/sbin/mdadm-fault-led.sh

	# modify mdadm configuration
	echo -e "\n # Trigger Fault Led script when an event is detected" >> $SDCARD/etc/mdadm/mdadm.conf
	echo -e "PROGRAM /usr/sbin/mdadm-fault-led.sh" >> $SDCARD/etc/mdadm/mdadm.conf

	### Ethernet tweaks

	# copy and enable helios4-wol.service
	cp $SRC/packages/bsp/helios4/helios4-wol.service $SDCARD/lib/systemd/system/
	chroot $SDCARD /bin/bash -c "systemctl --no-reload enable helios4-wol.service >/dev/null 2>&1"

	### Other tweaks

	# add custom motd default conf file
        cp $SRC/packages/bsp/helios4/armbian-motd $SDCARD/etc/default/

}
