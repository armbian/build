enable_extension "sunxi-tools"
export ARCH=armhf
export BOOTDELAY=1
export BOOTPATCHDIR='u-boot-sunxi'
UBOOT_TARGET_MAP="${UBOOT_TARGET_MAP:-;;u-boot-sunxi-with-spl.bin}"
export BOOTSCRIPT="boot-sunxi.cmd:boot.cmd"
export BOOTENV_FILE='sunxi.txt'
export LINUXFAMILY=sunxi
export UBOOT_FW_ENV='0x88000,0x20000' # /etc/fw_env.config offset and env size
export ASOUND_STATE='asound.state.sunxi-next'
export GOVERNOR=ondemand
export KERNELPATCHDIR='sunxi-'$BRANCH

case $BRANCH in

	legacy)
		export KERNEL_MAJOR_MINOR="5.10" # Major and minor versions of this kernel.
		export KERNELBRANCH="tag:v5.10.138"
		export KERNELBRANCH_MEGOUS="branch:orange-pi-5.10"
		;;

	current)
		export KERNEL_MAJOR_MINOR="5.15" # Major and minor versions of this kernel.
		export KERNELBRANCH="tag:v5.15.90"
		export KERNELBRANCH_MEGOUS="branch:orange-pi-5.15"
		;;

	edge)
		export KERNEL_MAJOR_MINOR="6.1" # Major and minor versions of this kernel.
		export KERNELBRANCH="tag:v6.1.8"
		export KERNELBRANCH_MEGOUS="branch:orange-pi-6.7"
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

family_tweaks_bsp() {
	# execute specific tweaks function if present
	[[ $(type -t family_tweaks_bsp_s) == function ]] && family_tweaks_bsp_s

	return 0 # short-circuit above, avoid errors on exit.
}

write_uboot_platform() {
	dd if=/dev/zero of=$2 bs=1k count=1023 seek=1 status=noxfer > /dev/null 2>&1
	dd if=$1/u-boot-sunxi-with-spl.bin of=$2 bs=1024 seek=8 status=noxfer > /dev/null 2>&1
}

setup_write_uboot_platform() {
	if grep -q "ubootpart" /proc/cmdline; then
		local tmp=$(cat /proc/cmdline)
		tmp="${tmp##*ubootpart=}"
		tmp="${tmp%% *}"
		[[ -n $tmp ]] && local part=$(findfs PARTUUID=$tmp 2> /dev/null)
		[[ -n $part ]] && local dev=$(lsblk -n -o PKNAME $part 2> /dev/null)
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
