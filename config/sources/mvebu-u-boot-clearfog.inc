case $BRANCH in
	default|next)
	BOOTSOURCE='https://github.com/SolidRun/u-boot-armada38x'
	BOOTBRANCH='branch:u-boot-2013.01-15t1-clearfog'
	BOOTDIR='u-boot-armada'
	BOOTSCRIPT='boot-marvell.cmd:boot.cmd'

	UBOOT_TARGET_MAP="u-boot.mmc;;u-boot.mmc u-boot-uart.mmc
		u-boot.sata;sata;u-boot.sata u-boot-uart.sata
		u-boot.flash;spi;u-boot.flash u-boot-uart.flash"

	UBOOT_USE_GCC='== 4.9'
	UBOOT_COMPILER='arm-linux-gnueabi-'

	BOOTPATCHDIR='u-boot-mvebu'
	;;
esac
