enable_extension "sunxi-tools"
export ARCH=arm64
export ATF_TARGET_MAP="PLAT=$ATF_PLAT DEBUG=1 bl31;;build/$ATF_PLAT/debug/bl31.bin"
export BOOTDELAY=1

export BOOTPATCHDIR='u-boot-sunxi'
export BOOTENV_FILE='sunxi.txt'
export UBOOT_TARGET_MAP=';;u-boot-sunxi-with-spl.bin'
export BOOTSCRIPT='boot-sun50i-next.cmd:boot.cmd'
export LINUXFAMILY=sunxi64
export KERNELPATCHDIR='sunxi-'$BRANCH

case $BRANCH in

	legacy)
		export KERNEL_MAJOR_MINOR="5.10" # Major and minor versions of this kernel.
		export KERNELBRANCH="branch:linux-5.10.y"
		export KERNELBRANCH_MEGOUS="branch:orange-pi-5.10"
		;;

	current)
		export KERNEL_MAJOR_MINOR="5.15" # Major and minor versions of this kernel.
		export KERNELBRANCH="branch:linux-5.15.y"
		export KERNELBRANCH_MEGOUS="branch:orange-pi-5.15"
		;;

	edge)
		export KERNEL_MAJOR_MINOR="5.19" # Major and minor versions of this kernel.
		export KERNELBRANCH="branch:linux-5.19.y"
		export KERNELBRANCH_MEGOUS="branch:orange-pi-5.19"
		;;
esac

# Hack for easily using megous for tests.
if [[ "$USE_MEGOUS" == "yes" ]]; then
	display_alert "Using megous/linux for kernel" "USE_MEGOUS: ${USE_MEGOUS}" "debug"
	export KERNELSOURCE="https://github.com/megous/linux"
	export KERNELBRANCH="${KERNELBRANCH_MEGOUS}"
fi

unset KERNELBRANCH_MEGOUS

family_tweaks() {
	# execute specific tweaks function if present
	[[ $(type -t family_tweaks_s) == function ]] && family_tweaks_s
	cp $SRC/packages/blobs/splash/armbian-u-boot-24.bmp $SDCARD/boot/boot.bmp
}

write_uboot_platform() {
	dd if=/dev/zero of=$2 bs=1k count=1023 seek=1 status=noxfer > /dev/null 2>&1
	dd if=$1/u-boot-sunxi-with-spl.bin of=$2 bs=1024 seek=8 status=noxfer > /dev/null 2>&1
}

setup_write_uboot_platform() {
	if grep -q "ubootpart" /proc/cmdline; then
		# mainline with new boot script
		local tmp=$(cat /proc/cmdline)
		tmp="${tmp##*ubootpart=}"
		tmp="${tmp%% *}"
		[[ -n $tmp ]] && local part=$(findfs PARTUUID=$tmp 2> /dev/null)
		[[ -n $part ]] && local dev=$(lsblk -n -o PKNAME $part 2> /dev/null)
		[[ -n $dev ]] && DEVICE="/dev/$dev"
	else
		# legacy or old boot script
		local tmp=$(cat /proc/cmdline)
		tmp="${tmp##*root=}"
		tmp="${tmp%% *}"
		[[ -n $tmp ]] && local part=$(findfs $tmp 2> /dev/null)
		[[ -n $part ]] && local dev=$(lsblk -n -o PKNAME $part 2> /dev/null)
		# do not try to write u-boot to USB devices
		[[ -n $dev && $dev == mmcblk* ]] && DEVICE="/dev/$dev"
	fi
}
