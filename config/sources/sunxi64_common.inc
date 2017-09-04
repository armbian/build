ARCH=arm64
KERNEL_IMAGE_TYPE=Image
HAS_UUID_SUPPORT=yes
OFFSET=2

case $BRANCH in
	default)
	CAN_BUILD_STRETCH=no
	;;

	next)
	;;

	dev)
	ATFSOURCE='https://github.com/apritzel/arm-trusted-firmware'
	ATFDIR='arm-trusted-firmware-sunxi-mainline'
	ATFBRANCH='branch:allwinner-stable'
	ATF_USE_GCC='> 6.0'
	ATF_TARGET_MAP='PLAT=sun50iw1p1 DEBUG=1 bl31;;build/sun50iw1p1/debug/bl31.bin'

	BOOTSOURCE=$MAINLINE_UBOOT_SOURCE
	BOOTDIR=$MAINLINE_UBOOT_DIR
	#BOOTBRANCH=$MAINLINE_UBOOT_BRANCH
	BOOTBRANCH='branch:master'
	BOOTPATCHDIR='u-boot-sun50i-dev'
	UBOOT_USE_GCC='> 7.0'
	UBOOT_TARGET_MAP=';;spl/sunxi-spl.bin u-boot.itb'
	BOOTSCRIPT='boot-sun50i-next.cmd:boot.cmd'

	KERNELSOURCE='https://github.com/Icenowy/linux/'
	KERNELBRANCH='branch:sunxi64-4.13.y'
	KERNELDIR='linux-sun50i-dev'
	KERNEL_USE_GCC='> 7.0'
	LINUXCONFIG='linux-sun50i-dev'
	KERNELPATCHDIR='sun50i-dev'
	;;
esac

write_uboot_platform()
{
	# default
	[[ -f $1/u-boot-with-dtb.bin ]] && dd if=$1/u-boot-with-dtb.bin of=$2 bs=1k seek=8 conv=fsync > /dev/null 2>&1 || true
	# mainline
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
