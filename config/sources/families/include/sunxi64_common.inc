#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
enable_extension "sunxi-tools"
declare -g ARCH=arm64
declare -g ATF_TARGET_MAP="PLAT=$ATF_PLAT DEBUG=1 bl31;;build/$ATF_PLAT/debug/bl31.bin"
declare -g BOOTDELAY=1
declare -g BOOTPATCHDIR="${BOOTPATCHDIR:-"u-boot-sunxi"}"
declare -g BOOTBRANCH="${BOOTBRANCH:-"tag:v2022.10"}"
declare -g BOOTENV_FILE='sunxi.txt'
UBOOT_TARGET_MAP="${UBOOT_TARGET_MAP:-;;u-boot-sunxi-with-spl.bin}"
declare -g BOOTSCRIPT='boot-sun50i-next.cmd:boot.cmd'
declare -g LINUXFAMILY=sunxi64
declare -g CRUST_TARGET_MAP="scp;;build/scp/scp.bin"

[[ -n "${CRUSTCONFIG}" && -z $CRUSTSOURCE ]] && CRUSTSOURCE='https://github.com/crust-firmware/crust'
[[ -n "${CRUSTCONFIG}" && -z $CRUSTDIR ]] && CRUSTDIR='crust-sunxi-mainline'
[[ -n "${CRUSTCONFIG}" && -z $CRUSTBRANCH ]] && CRUSTBRANCH='commit:c308a504853e7fdb47169796c9a832796410ece8'
[[ -n "${CRUSTCONFIG}" && -z $CRUST_USE_GCC ]] && CRUST_USE_GCC='> 9.1.0'
[[ -n "${CRUSTCONFIG}" && -z $CRUST_COMPILER ]] && CRUST_COMPILER='or1k-elf-'

# Apply crust patches if crust is enabled
[[ -n "${CRUSTCONFIG}" ]] && BOOTPATCHDIR="${BOOTPATCHDIR} u-boot-sunxi-crust"

case $BRANCH in

	legacy)
		declare -g KERNEL_MAJOR_MINOR="5.15" # Major and minor versions of this kernel.
		declare -g KERNELBRANCH="tag:v5.15.113"
		;;

	current)
		declare -g KERNEL_MAJOR_MINOR="6.1" # Major and minor versions of this kernel.
		declare -g KERNELBRANCH="tag:v6.1.34"
		;;

	edge)
		declare -g KERNEL_MAJOR_MINOR="6.2" # Major and minor versions of this kernel.
		declare -g KERNELBRANCH="tag:v6.2.16"
		;;
esac

KERNELPATCHDIR="archive/sunxi-${KERNEL_MAJOR_MINOR}"

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
