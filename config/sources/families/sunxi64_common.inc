ARCH=arm64
KERNEL_IMAGE_TYPE=Image
BOOTDELAY=1

BOOTSOURCE=$MAINLINE_UBOOT_SOURCE
BOOTDIR=$MAINLINE_UBOOT_DIR
BOOTBRANCH='tag:v2019.04'
BOOTPATCHDIR='u-boot-sunxi'
UBOOT_USE_GCC='> 7.0'
UBOOT_TARGET_MAP=';;spl/sunxi-spl.bin u-boot.itb'
BOOTSCRIPT='boot-sun50i-next.cmd:boot.cmd'
LINUXFAMILY=sunxi64

case $BRANCH in
	next|legacy)

		ATFSOURCE='https://github.com/ARM-software/arm-trusted-firmware'
		ATFDIR='arm-trusted-firmware-sunxi-mainline'
		ATFBRANCH='branch:master'
		ATF_USE_GCC='> 6.3'
		ATF_TARGET_MAP="PLAT=$ATF_PLAT DEBUG=1 bl31;;build/$ATF_PLAT/debug/bl31.bin"

		KERNELSOURCE=$MAINLINE_KERNEL_SOURCE
		KERNELBRANCH='branch:linux-4.19.y'
		KERNELDIR=$MAINLINE_KERNEL_DIR
		KERNELPATCHDIR='sunxi-next'
		KERNEL_USE_GCC='> 7.0'

	;;

	dev|current)

		ATFSOURCE='https://github.com/ARM-software/arm-trusted-firmware'
		ATFDIR='arm-trusted-firmware-sunxi-mainline'
		ATFBRANCH='branch:master'
		ATF_USE_GCC='> 6.3'
		ATF_TARGET_MAP="PLAT=$ATF_PLAT DEBUG=1 bl31;;build/$ATF_PLAT/debug/bl31.bin"

		#KERNELSOURCE=$MAINLINE_KERNEL_SOURCE
		KERNELSOURCE="https://github.com/megous/linux"
		KERNELBRANCH="branch:orange-pi-5.3"
		KERNELDIR=$MAINLINE_KERNEL_DIR
		KERNELPATCHDIR='sunxi-'$BRANCH
		KERNEL_USE_GCC='> 7.0'
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
	[[ -f $1/sunxi-spl.bin ]] && dd if=$1/sunxi-spl.bin of=$2 bs=8k seek=1 conv=fsync > /dev/null 2>&1
	[[ -f $1/u-boot.itb ]] && dd if=$1/u-boot.itb of=$2 bs=8k seek=5 conv=fsync > /dev/null 2>&1 || true
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
