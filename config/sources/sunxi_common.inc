
BOOTSOURCE=$MAINLINE_UBOOT_SOURCE
BOOTDIR=$MAINLINE_UBOOT_DIR
BOOTBRANCH=$MAINLINE_UBOOT_BRANCH
BOOTSCRIPT="boot-sunxi.cmd:boot.cmd"

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
