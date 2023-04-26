#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
enable_extension "sunxi-tools"
declare -g ARCH=armhf
declare -g BOOTDELAY=1
declare -g BOOTPATCHDIR='u-boot-sunxi'
UBOOT_TARGET_MAP="${UBOOT_TARGET_MAP:-;;u-boot-sunxi-with-spl.bin}"
declare -g BOOTSCRIPT="boot-sunxi.cmd:boot.cmd"
declare -g BOOTENV_FILE='sunxi.txt'
declare -g LINUXFAMILY=sunxi
declare -g UBOOT_FW_ENV='0x88000,0x20000' # /etc/fw_env.config offset and env size
declare -g ASOUND_STATE='asound.state.sunxi-next'
declare -g GOVERNOR=ondemand

case $BRANCH in

	legacy)
		declare -g KERNEL_MAJOR_MINOR="5.15" # Major and minor versions of this kernel.
		declare -g KERNELBRANCH="tag:v5.15.108"
		;;

	current)
		declare -g KERNEL_MAJOR_MINOR="6.1" # Major and minor versions of this kernel.
		declare -g KERNELBRANCH="tag:v6.1.26"
		;;

	edge)
		declare -g KERNEL_MAJOR_MINOR="6.2" # Major and minor versions of this kernel.
		declare -g KERNELBRANCH="tag:v6.2.13"
		;;
esac

KERNELPATCHDIR="archive/sunxi-${KERNEL_MAJOR_MINOR}"

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
