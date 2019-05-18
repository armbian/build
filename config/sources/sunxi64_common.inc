ARCH=arm64
KERNEL_IMAGE_TYPE=Image
BOOTDELAY=1

BOOTSOURCE=$MAINLINE_UBOOT_SOURCE
BOOTDIR=$MAINLINE_UBOOT_DIR
BOOTBRANCH='tag:v2019.01'
BOOTPATCHDIR='u-boot-sunxi'
UBOOT_USE_GCC='> 7.0'
UBOOT_TARGET_MAP=';;spl/sunxi-spl.bin u-boot.itb'
BOOTSCRIPT='boot-sun50i-next.cmd:boot.cmd'

ATF_PLAT="sun50i_a64"

if [[ $BOARDFAMILY = "sun50iw6" ]]; then
    ATF_PLAT="sun50i_h6";
fi

# Here we want to rename LINUXFAMILY from sun50iw1, sun50iw2, etc for next and dev branches
# since this doesn't affect any stable images don't add any backwards compatibility hacks
[[ $BRANCH != default ]] && LINUXFAMILY=sunxi64

case $BRANCH in
	default)

		CAN_BUILD_STRETCH=no

	;;

	next)

		ATFSOURCE='https://github.com/ARM-software/arm-trusted-firmware'
		ATFDIR='arm-trusted-firmware-sunxi-mainline'
		ATFBRANCH='branch:master'
		ATF_USE_GCC='> 6.3'
		ATF_TARGET_MAP="PLAT=$ATF_PLAT DEBUG=1 bl31;;build/$ATF_PLAT/debug/bl31.bin"

		KERNELSOURCE="https://github.com/megous/linux"
		KERNELBRANCH="branch:orange-pi-4.19"
		KERNELDIR=$MAINLINE_KERNEL_DIR
		KERNELPATCHDIR='sunxi-next'
		KERNEL_USE_GCC='> 7.0'

	;;

	dev)

		ATFSOURCE='https://github.com/ARM-software/arm-trusted-firmware'
		ATFDIR='arm-trusted-firmware-sunxi-mainline'
		ATFBRANCH='branch:master'
		ATF_USE_GCC='> 6.3'
		ATF_TARGET_MAP="PLAT=$ATF_PLAT DEBUG=1 bl31;;build/$ATF_PLAT/debug/bl31.bin"

		#KERNELSOURCE=$MAINLINE_KERNEL_SOURCE
		KERNELSOURCE="https://github.com/megous/linux"
		#KERNELBRANCH='branch:linux-4.19.y'
		KERNELBRANCH="branch:orange-pi-5.0"
		KERNELDIR=$MAINLINE_KERNEL_DIR
		KERNELPATCHDIR='sunxi-dev'
		KERNEL_USE_GCC='> 7.0'
	;;
esac

family_tweaks()
{
	# execute specific tweaks function if present
	[[ $(type -t family_tweaks_s) == function ]] && family_tweaks_s
}

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
