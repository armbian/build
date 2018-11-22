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
	BOOTSCRIPT='boot-mvebu-next.cmd:boot.cmd'
	BOOTCONFIG='helios4_defconfig'

	UBOOT_TARGET_MAP=";;u-boot-spl.kwb:u-boot.mmc
		;spi;u-boot-spl.kwb:u-boot.flash"
	UBOOT_USE_GCC='> 7.0'

	OVERLAY_PREFIX='armada-388-helios4'

	BOOTPATCHDIR='u-boot-helios4-next'
	;;
esac


# Helios4 tweak : install and configure fancontrol
family_tweaks_s()
{
	chroot $SDCARD /bin/bash -c "apt-get -y -qq install fancontrol >/dev/null 2>&1"
	patch $SDCARD/usr/sbin/fancontrol $SRC/packages/bsp/helios4/fancontrol.patch
	cp -R $SRC/packages/bsp/helios4/90-helios4-hwmon.rules $SDCARD/etc/udev/rules.d/
	case $BRANCH in
	default)
		cp -R $SRC/packages/bsp/helios4/fancontrol_pwm-fan-mvebu-default.conf $SDCARD/etc/fancontrol
		;;

	next)
		cp -R $SRC/packages/bsp/helios4/fancontrol_pwm-fan-mvebu-next.conf $SDCARD/etc/fancontrol
		;;
	esac
}

