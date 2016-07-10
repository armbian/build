
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

install_boot_script()
{
	cp $SRC/lib/config/bootscripts/boot-sunxi.cmd $CACHEDIR/sdcard/boot/boot.cmd

	# orangepi h3 temp exceptions
	[[ $LINUXFAMILY == sun8i ]] && sed -i -e '1s/^/gpio set PL10\ngpio set PG11\nsetenv machid 1029\nsetenv bootm_boot_mode sec\n/' \
		-e 's/\ disp.screen0_output_mode=1920x1080p60//' -e 's/\ hdmi.audio=EDID:0//' $CACHEDIR/sdcard/boot/boot.cmd
}
