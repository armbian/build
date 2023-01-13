enable_extension "sunxi-tools"
ARCH=arm64
ATF_TARGET_MAP="PLAT=$ATF_PLAT DEBUG=1 bl31;;build/$ATF_PLAT/debug/bl31.bin"
BOOTDELAY=1

BOOTPATCHDIR='u-boot-sunxi'
BOOTENV_FILE='sunxi.txt'
UBOOT_TARGET_MAP="${UBOOT_TARGET_MAP:-;;u-boot-sunxi-with-spl.bin}"
BOOTSCRIPT='boot-sun50i-next.cmd:boot.cmd'
LINUXFAMILY=sunxi64

case $BRANCH in

	legacy)
		KERNEL_VERSION_LEVEL="5.10"
		KERNELSWITCHOBJ="tag=v5.10.138"
		;;

	current)
		KERNEL_VERSION_LEVEL="5.15"
		KERNELSWITCHOBJ="tag=v5.15.87"
		;;

	edge)
		KERNEL_VERSION_LEVEL=${KERNEL_VERSION_LEVEL:-6.1}
		KERNELSWITCHOBJ=${KERNELSWITCHOBJ:-'tag=v6.1.5'}
		;;
esac

case "$KERNEL_VERSION_LEVEL" in

	5.10|5.15|5.16|5.17|5.18|5.19|6.0|6.1)
		KERNELSOURCE=$MAINLINE_KERNEL_SOURCE
		KERNELSOURCENAME='name=origin'
		KERNELBRANCH="branch:linux-${KERNEL_VERSION_LEVEL}.y"
		;;

	*)
		KERNELSOURCE="https://github.com/megous/linux"
		KERNELSOURCENAME='name=megous'
		KERNELBRANCH="branch:orange-pi-$KERNEL_VERSION_LEVEL"
		;;
esac

KERNELPATCHDIR='archive/sunxi-'$KERNEL_VERSION_LEVEL

# An optional parameter for switching to a git object such as a tag, commit,
# or a specific branch. The object must exist in the local repository.
# This optional parameter takes precedence. If it is specified, then
# the commit state corresponding to the specified git object will be extracted
# to the working directory. Otherwise, the commit corresponding to the top of
# the branch will be extracted.
# KERNELSWITCHOBJ="tag=v5.10.15"
# tag | obj | commit=v5.10.15 | [origin|megous]/$branch | $hash

var_origin_kernel() {
	url=$MAINLINE_KERNEL_SOURCE
	name='origin'
	branch="linux-${KERNEL_VERSION_LEVEL}.y"
	start_tag="v$KERNEL_VERSION_LEVEL"

	# checking the reachability of the initial tag
	if [ "$(git ls-remote --tags $url $start_tag |
		awk -F'/' '{if (NR == 1) print $NF}')" != "$start_tag" ]; then
		exit 177
	fi

	# Exceptions to the rule are when the desired tag is not
	# a bifurcation point at which all previous merge branches converge.
	# This is due to the subsequent extraction of `megous`
	# [ "$KERNEL_VERSION_LEVEL" == "5.12" ] && start_tag="v5.12-rc7"
}

family_tweaks() {
	if [[ $BOARD == nanopi-r1s-h5 ]]; then
		# rename USB based network to lan0
		mkdir -p $SDCARD/etc/udev/rules.d/
		echo 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="r8152", KERNEL=="eth1", NAME="lan0"' > $SDCARD/etc/udev/rules.d/70-rename-lan.rules
	fi

	# execute specific tweaks function if present
	[[ $(type -t family_tweaks_s) == function ]] && family_tweaks_s
	cp $SRC/packages/blobs/splash/armbian-u-boot-24.bmp $SDCARD/boot/boot.bmp
}

case $IMAGE_PARTITION_TABLE in
	msdos)
		write_uboot_platform() {
			dd if=/dev/zero of=$2 bs=1k count=1023 seek=1 status=noxfer > /dev/null 2>&1
			dd if=$1/u-boot-sunxi-with-spl.bin of=$2 bs=1024 seek=8 status=noxfer > /dev/null 2>&1
		}
		;;

	gpt) # Skip 128K for writing if the partition table is GPT.
		write_uboot_platform() {
			dd if=/dev/zero of=$2 bs=1024 count=1023 seek=128 status=noxfer > /dev/null 2>&1
			dd if=$1/u-boot-sunxi-with-spl.bin of=$2 bs=1024 seek=128 status=noxfer > /dev/null 2>&1
		}
		;;
esac

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
