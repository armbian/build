ARCH=arm64
ATF_TARGET_MAP="PLAT=$ATF_PLAT DEBUG=1 bl31;;build/$ATF_PLAT/debug/bl31.bin"
BOOTDELAY=1
BOOTBRANCH='tag:v2020.10'
BOOTPATCHDIR='u-boot-sunxi'
BOOTENV_FILE='sunxi.txt'
UBOOT_TARGET_MAP=';;u-boot-sunxi-with-spl.bin'
BOOTSCRIPT='boot-sun50i-next.cmd:boot.cmd'
LINUXFAMILY=sunxi64

case $BRANCH in
	legacy)
		
		KERNELSOURCE="https://github.com/megous/linux"
		KERNELBRANCH="branch:orange-pi-5.4"
		KERNELPATCHDIR='sunxi-'$BRANCH

	;;

	current)

		KERNELSOURCE="https://github.com/megous/linux"
		KERNELBRANCH="branch:orange-pi-5.10"
		KERNELPATCHDIR='sunxi-'$BRANCH

	;;

	dev)

		KERNELSOURCE="https://github.com/megous/linux"
		KERNELBRANCH="branch:orange-pi-5.10"
		KERNELPATCHDIR='sunxi-'$BRANCH

	;;
esac

family_tweaks()
{
	# execute specific tweaks function if present
	[[ $(type -t family_tweaks_s) == function ]] && family_tweaks_s
	cp $SRC/packages/blobs/splash/armbian-u-boot-24.bmp $SDCARD/boot/boot.bmp
}

write_uboot_platform()
{
	dd if=/dev/zero of=$2 bs=1k count=1023 seek=1 status=noxfer > /dev/null 2>&1
	dd if=$1/u-boot-sunxi-with-spl.bin of=$2 bs=1024 seek=8 status=noxfer > /dev/null 2>&1
}

setup_write_uboot_platform()
{
	if grep -q "ubootpart" /proc/cmdline; then
		# mainline with new boot script
		local tmp=$(cat /proc/cmdline)
		tmp="${tmp##*ubootpart=}"
		tmp="${tmp%% *}"
		[[ -n $tmp ]] && local part=$(findfs PARTUUID=$tmp 2>/dev/null)
		[[ -n $part ]] && local dev=$(lsblk -n -o PKNAME $part 2>/dev/null)
		[[ -n $dev ]] && DEVICE="/dev/$dev"
	else
		# legacy or old boot script
		local tmp=$(cat /proc/cmdline)
		tmp="${tmp##*root=}"
		tmp="${tmp%% *}"
		[[ -n $tmp ]] && local part=$(findfs $tmp 2>/dev/null)
		[[ -n $part ]] && local dev=$(lsblk -n -o PKNAME $part 2>/dev/null)
		# do not try to write u-boot to USB devices
		[[ -n $dev && $dev == mmcblk* ]] && DEVICE="/dev/$dev"
	fi
}
