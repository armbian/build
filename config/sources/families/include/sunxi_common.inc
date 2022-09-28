enable_extension "sunxi-tools"
ARCH=armhf
BOOTDELAY=1
BOOTPATCHDIR='u-boot-sunxi'
UBOOT_TARGET_MAP=';;u-boot-sunxi-with-spl.bin'
BOOTSCRIPT="boot-sunxi.cmd:boot.cmd"
BOOTENV_FILE='sunxi.txt'
LINUXFAMILY=sunxi
UBOOT_FW_ENV='0x88000,0x20000' # /etc/fw_env.config offset and env size
ASOUND_STATE='asound.state.sunxi-next'
GOVERNOR=ondemand

case $BRANCH in

	legacy)
		KERNEL_VERSION_LEVEL="5.10"
		KERNELSWITCHOBJ="tag=v5.10.138"
		;;
	current)
		KERNEL_VERSION_LEVEL="5.15"
		KERNELSWITCHOBJ="tag=v5.15.71"
		;;
	edge)
		KERNEL_VERSION_LEVEL=${KERNEL_VERSION_LEVEL:-5.19}
		KERNELSWITCHOBJ=${KERNELSWITCHOBJ:-'tag=v5.19.12'}
		;;

esac

case "$KERNEL_VERSION_LEVEL" in

	5.10|5.15|5.16|5.17|5.18|5.19)
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

var_origin_kernel ()
{
	url=$MAINLINE_KERNEL_SOURCE
	name='origin'
	branch="linux-${KERNEL_VERSION_LEVEL}.y"
	start_tag="v$KERNEL_VERSION_LEVEL"

	# checking the reachability of the initial tag
	if [ "$(git ls-remote --tags $url $start_tag | \
		awk -F'/' '{if (NR == 1) print $NF}')" != "$start_tag" ];then
		exit 177
	fi

	# Exceptions to the rule are when the desired tag is not
	# a bifurcation point at which all previous merge branches converge.
	# This is due to the subsequent extraction of `megous`
	# [ "$KERNEL_VERSION_LEVEL" == "5.12" ] && start_tag="v5.12-rc7"
}

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

