BOOTSOURCE=$MAINLINE_UBOOT_SOURCE
BOOTDIR=$MAINLINE_UBOOT_DIR
BOOTBRANCH='tag:v2017.11'
BOOTSCRIPT="boot-sunxi.cmd:boot.cmd"
BOOTENV_FILE='sunxi-default.txt'
BOOTPATCHDIR='u-boot-sunxi'

UBOOT_TARGET_MAP=';;u-boot-sunxi-with-spl.bin'

UBOOT_USE_GCC='> 7.0'
UBOOT_FW_ENV='0x88000,0x20000' # /etc/fw_env.config offset and env size

BOOTDELAY=1

# Here we want to rename LINUXFAMILY from sun4i, sun5i, etc for next and dev branches
[[ $BRANCH != default ]] && LINUXFAMILY=sunxi

case $BRANCH in
	default)
	GOVERNOR=interactive
	CAN_BUILD_STRETCH=no
	;;

	next)
	KERNELSOURCE=$MAINLINE_KERNEL_SOURCE
	KERNELBRANCH='branch:linux-4.14.y'
	KERNELDIR=$MAINLINE_KERNEL_DIR

	GOVERNOR=ondemand

	KERNEL_USE_GCC='> 7.0'
	;;

	dev)
	BOOTBRANCH='tag:v2018.05'
	BOOTPATCHDIR='u-boot-sunxi-dev'

	GOVERNOR=ondemand
	KERNELSOURCE=$MAINLINE_KERNEL_SOURCE
	KERNELBRANCH='branch:linux-4.17.y'
	KERNELDIR=$MAINLINE_KERNEL_DIR
	KERNEL_USE_GCC='> 7.0'
	;;
esac

family_tweaks()
{
	# execute specific tweaks function if present
	[[ $(type -t family_tweaks_s) == function ]] && family_tweaks_s

	cp $SRC/packages/blobs/splash/armbian-u-boot-24.bmp $SDCARD/boot/boot.bmp
}

family_tweaks_bsp()
{
	# execute specific tweaks function if present
	[[ $(type -t family_tweaks_bsp_s) == function ]] && family_tweaks_bsp_s

	if [[ $BRANCH == default ]]; then
		arm-linux-gnueabihf-gcc $SRC/packages/bsp/sunxi-temp/sunxi_tp_temp.c -o $destination/usr/bin/sunxi_tp_temp
		# convert and add fex files
		mkdir -p $destination/boot/bin
		for i in $(ls -w1 $SRC/config/fex/*.fex | xargs -n1 basename); do
			fex2bin $SRC/config/fex/${i%*.fex}.fex $destination/boot/bin/${i%*.fex}.bin
		done
	fi
}

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
