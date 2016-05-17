
BOOTLOADER=$MAINLINE_UBOOT
BOOTSOURCE=$MAINLINE_UBOOT_SOURCE
BOOTBRANCH=$MAINLINE_UBOOT_BRANCH

case $BRANCH in
	default)
	GOVERNOR=interactive
	;;

	next)
	GOVERNOR=ondemand
	;;

	dev)
	GOVERNOR=ondemand
	;;
esac

UBOOT_FILES="u-boot-sunxi-with-spl.bin"

write_uboot_platform()
{
	dd if=/dev/zero of=$2 bs=1k count=1023 seek=1 status=noxfer > /dev/null 2>&1
	dd if=$1/u-boot-sunxi-with-spl.bin of=$2 bs=1024 seek=8 status=noxfer > /dev/null 2>&1
}

family_tweaks()
{
	# default lirc configuration
	sed -i '1i sed -i \x27s/DEVICE="\\/dev\\/input.*/DEVICE="\\/dev\\/input\\/\x27$str\x27"/g\x27 /etc/lirc/hardware.conf' \
		$CACHEDIR/sdcard/etc/lirc/hardware.conf
	sed -i '1i str=$(cat /proc/bus/input/devices | grep "H: Handlers=sysrq rfkill kbd event" | awk \x27{print $(NF)}\x27)' \
		$CACHEDIR/sdcard/etc/lirc/hardware.conf
	sed -i '1i # Cubietruck automatic lirc device detection by Igor Pecovnik' $CACHEDIR/sdcard/etc/lirc/hardware.conf
	sed -e 's/DEVICE=""/DEVICE="\/dev\/input\/event1"/g' -i $CACHEDIR/sdcard/etc/lirc/hardware.conf
	sed -e 's/DRIVER="UNCONFIGURED"/DRIVER="devinput"/g' -i $CACHEDIR/sdcard/etc/lirc/hardware.conf
	cp $SRC/lib/config/lirc.conf.cubietruck $CACHEDIR/sdcard/etc/lirc/lircd.conf
}
