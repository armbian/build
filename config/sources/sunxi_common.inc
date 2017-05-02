BOOTSOURCE=$MAINLINE_UBOOT_SOURCE
BOOTDIR=$MAINLINE_UBOOT_DIR
BOOTBRANCH=$MAINLINE_UBOOT_BRANCH
BOOTSCRIPT="boot-sunxi.cmd:boot.cmd"
BOOTENV_FILE='sunxi-default.txt'
BOOTPATCHDIR='u-boot-sunxi'

UBOOT_TARGET_MAP=';;u-boot-sunxi-with-spl.bin'

UBOOT_USE_GCC='> 6.0'
UBOOT_FW_ENV='0x88000,0x20000' # /etc/fw_env.config offset and env size

HAS_UUID_SUPPORT=yes
BOOTDELAY=0

# Here we want to rename LINUXFAMILY from sun4i, sun5i, etc for next and dev branches
# except for sun8i-dev which is separate from sunxi-dev
[[ $BRANCH != default && ! ( $LINUXFAMILY == sun8i && $BRANCH == dev ) ]] && LINUXFAMILY=sunxi

case $BRANCH in
	default)
	GOVERNOR=interactive
	;;

	next)
	KERNELSOURCE=$MAINLINE_KERNEL_SOURCE
	KERNELBRANCH=$MAINLINE_KERNEL_BRANCH
	KERNELDIR=$MAINLINE_KERNEL_DIR

	GOVERNOR=ondemand

	KERNEL_USE_GCC='> 6.0'
	;;

	dev)
	GOVERNOR=ondemand

	KERNEL_USE_GCC='> 6.0'
	;;
esac

write_uboot_platform()
{
	dd if=/dev/zero of=$2 bs=1k count=1023 seek=1 status=noxfer > /dev/null 2>&1
	dd if=$1/u-boot-sunxi-with-spl.bin of=$2 bs=1024 seek=8 status=noxfer > /dev/null 2>&1
}

setup_write_uboot_platform()
{
	if grep -q "ubootpart" /proc/cmdline; then
		local tmp=$(cat /proc/cmdline)
		tmp="${tmp##*ubootpart=}"
		tmp="${tmp%% *}"
		[[ -n $tmp ]] && local part=$(findfs PARTUUID=$tmp 2>/dev/null)
		[[ -n $part ]] && local dev=$(lsblk -n -o PKNAME $part 2>/dev/null)
		[[ -n $dev ]] && DEVICE="/dev/$dev"
	elif [[ -f /var/lib/armbian/force_search_uboot ]]; then
		# This may cause overwriting u-boot for android or other non-Armbian OS installed on eMMC
		# so don't run this function by default
		for dev in $(lsblk -d -n -p -o NAME); do
			if grep -q 'eGON.BT0' <(dd if=$dev bs=32 skip=256 count=1 status=none); then
				# Assuming that only one device with SPL signature is present
				echo "SPL signature found on $dev" >&2
				DEVICE=$dev
				break
			fi
		done
	fi
}
