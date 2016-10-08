
BOOTSOURCE=$MAINLINE_UBOOT_SOURCE
BOOTDIR=$MAINLINE_UBOOT_DIR
BOOTBRANCH=$MAINLINE_UBOOT_BRANCH

case $BRANCH in
	default)
	GOVERNOR=interactive
	;;

	next)
	GOVERNOR=schedutil
	;;

	dev)
	GOVERNOR=schedutil
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
	if [[ $LINUXFAMILY == sun8i ]]; then
		# u-boot default is nonsec. Legacy requires sec, mainline requires nonsec for SMP
		local boot_mode=nonsec
		[[ $BRANCH == default ]] && boot_mode=sec
		sed -i -e "1s/^/gpio set PL10\ngpio set PG11\nsetenv machid 1029\nsetenv bootm_boot_mode $boot_mode\n/" \
			-e 's/\ disp.screen0_output_mode=1920x1080p60//' -e 's/\ hdmi.audio=EDID:0//' $CACHEDIR/sdcard/boot/boot.cmd
	fi
}
