ARCH=arm64
KERNEL_IMAGE_TYPE=Image
HAS_UUID_SUPPORT=yes
OFFSET=2

case $BRANCH in
	default)
	CAN_BUILD_STRETCH=no
	;;

	dev)
	ATFSOURCE='https://github.com/apritzel/arm-trusted-firmware'
	ATFDIR='arm-trusted-firmware-sunxi-mainline'
	ATFBRANCH='branch:allwinner-stable'
	ATF_USE_GCC='> 6.0'
	ATF_TARGET_MAP='PLAT=sun50iw1p1 DEBUG=1 bl31;;build/sun50iw1p1/debug/bl31.bin'

	BOOTSOURCE='https://github.com/zador-blood-stained/u-boot-sun50i.git'
	BOOTDIR='u-boot-sun50i'
	BOOTBRANCH='branch:master'
	BOOTPATCHDIR='u-boot-sun50i-dev'
	UBOOT_USE_GCC='> 7.0'
	UBOOT_TARGET_MAP="$BOARD;;u-boot-sunxi-with-spl.bin"
	BOOTSCRIPT='boot-sun50i-next.cmd:boot.cmd'

	KERNELSOURCE='https://github.com/Icenowy/linux/'
	KERNELBRANCH='branch:sunxi64-4.11.y'
	KERNELDIR='linux-sun50i-dev'
	KERNEL_USE_GCC='> 7.0'
	LINUXCONFIG='linux-sun50i-dev'
	KERNELPATCHDIR='sun50i-dev'
	;;
esac

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
