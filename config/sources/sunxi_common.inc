
BOOTLOADER=$MAINLINE_UBOOT
BOOTSOURCE=$MAINLINE_UBOOT_SOURCE

case $BRANCH in
	default)
	BOOTBRANCH=$MAINLINE_UBOOT_BRANCH
	GOVERNOR=interactive
	;;

	next)
	BOOTBRANCH=$MAINLINE_UBOOT_BRANCH
	GOVERNOR=ondemand
	;;

	dev)
	BOOTBRANCH=''
	GOVERNOR=ondemand
	;;
esac

UBOOT_FILES="u-boot-sunxi-with-spl.bin"

write_uboot_platform()
{
	dd if=/dev/zero of=$2 bs=1k count=1023 seek=1 status=noxfer > /dev/null 2>&1
	dd if=$1/u-boot-sunxi-with-spl.bin of=$2 bs=1024 seek=8 status=noxfer > /dev/null 2>&1
}
