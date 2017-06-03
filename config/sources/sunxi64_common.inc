ARCH=arm64
KERNEL_IMAGE_TYPE=Image
HAS_UUID_SUPPORT=yes
OFFSET=2

case $BRANCH in
	dev)
	BOOTSOURCE='https://github.com/zador-blood-stained/u-boot-sun50i.git'
	BOOTDIR='u-boot-sun50i'
	BOOTBRANCH='branch:master'
	BOOTPATCHDIR='u-boot-sun50i-dev'
	UBOOT_TARGET_MAP="$BOARD;;u-boot-sunxi-with-spl.bin"
	BOOTSCRIPT='boot-sun50i-next.cmd:boot.cmd'

	KERNELSOURCE='https://github.com/Icenowy/linux/'
	KERNELBRANCH='branch:sunxi64-4.11.y'
	KERNELDIR='linux-sun50i-dev'
	KERNEL_USE_GCC='> 6.1'
	LINUXCONFIG='linux-sun50i-dev'
	KERNELPATCHDIR='sun50i-dev'
	;;
esac

setup_write_uboot_platform()
{
	if grep -q "ubootpart" /proc/cmdline; then
		# mainline
		local tmp=$(cat /proc/cmdline)
		tmp="${tmp##*ubootpart=}"
		tmp="${tmp%% *}"
		[[ -n $tmp ]] && local part=$(findfs PARTUUID=$tmp 2>/dev/null)
		[[ -n $part ]] && local dev=$(lsblk -n -o PKNAME $part 2>/dev/null)
		[[ -n $dev ]] && DEVICE="/dev/$dev"
	else
		# legacy
		local tmp=$(cat /proc/cmdline)
		tmp="${tmp##*root=}"
		tmp="${tmp%% *}"
		[[ -n $tmp ]] && local part=$(findfs $tmp 2>/dev/null)
		[[ -n $part ]] && local dev=$(lsblk -n -o PKNAME $part 2>/dev/null)
		[[ -n $dev ]] && DEVICE="/dev/$dev"
	fi
}
