case $BRANCH in
	default|next)
	BOOTSOURCE='https://github.com/helios-4/u-boot-marvell.git'
	BOOTBRANCH='branch:u-boot-2013.01-15t1-helios4'
	BOOTDIR='u-boot-armada'
	BOOTSCRIPT='boot-marvell.cmd:boot.cmd'

	UBOOT_TARGET_MAP="u-boot.mmc;;u-boot.mmc"

	UBOOT_USE_GCC='== 4.9'
	UBOOT_COMPILER='arm-linux-gnueabi-'

	BOOTPATCHDIR='u-boot-helios4'
	;;
esac


# Helios4 tweak : install and configure fancontrol
family_tweaks_s()
{
	chroot $SDCARD /bin/bash -c "apt-get -y -qq install fancontrol >/dev/null 2>&1"
	case $BRANCH in
	default)
		cp -R $SRC/packages/bsp/helios4/fancontrol_gpio-fan.conf $SDCARD/etc/fancontrol
		;;

	next)
		cp -R $SRC/packages/bsp/helios4/fancontrol_pwm-fan.conf $SDCARD/etc/fancontrol
		patch $SDCARD/usr/sbin/fancontrol < $SRC/packages/bsp/helios4/fancontrol.patch
		;;
	esac
}

