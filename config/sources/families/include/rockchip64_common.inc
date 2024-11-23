#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
enable_extension "rkbin-tools"
ARCH=arm64
OFFSET=16
BOOTSCRIPT='boot-rockchip64.cmd:boot.cmd'
BOOTENV_FILE='rockchip64.txt'
UBOOT_TARGET_MAP=";;idbloader.bin uboot.img trust.bin"
BOOTDELAY=0
OVERLAY_PREFIX="${OVERLAY_PREFIX:-"rockchip"}" # default to 'rockchip' if not set by board
OVERLAY_DIR="/boot/dtb/rockchip/overlay"
# SERIALCON is handled/defaulted in hook post_family_config__900_late_default_serial_console_by_branch at end of this file
GOVERNOR="ondemand"
ATFPATCHDIR='atf-rockchip64'
BOOTPATCHDIR="${BOOTPATCHDIR:-"u-boot-rockchip64"}"
PACKAGE_LIST_FAMILY="ethtool"
RKBIN_DIR="$SRC/cache/sources/rkbin-tools"

# Important, we don't set LINUXFAMILY and LINUXCONFIG -- unless it is current or edge. Specifically, we don't do it for legacy branches, which are used by BOARDFAMILY's other than rockchip64.

case $BRANCH in

	current)
		declare -g KERNEL_MAJOR_MINOR="6.6"
		declare -g LINUXFAMILY=rockchip64
		declare -g LINUXCONFIG='linux-rockchip64-'$BRANCH
		;;

	edge)
		declare -g KERNEL_MAJOR_MINOR="6.12"
		declare -g LINUXFAMILY=rockchip64
		declare -g LINUXCONFIG='linux-rockchip64-'$BRANCH
		;;
esac

# rockchip64 (used mainly for RK3399) legacy kernel 4.4 is dead code

# Common variables:
# BOOT_SCENARIO - determines which tpl (ddrbin), spl and ATF combination to use
#
# Different boot scenario can arrange:
# * Phase 1: DDR initialization (proprietary rockchip ddrbin or u-boot TPL)
# * Phase 2: Initial system and clock initialization (proprietary rockchip miniload or u-boot SPL)
# * Phase 3: Arm Trusted Firmware (proprietary rockchip or mainline opensource)
# * Phase 4: u-boot proper is always the mainline one
#
# Available options for BOOT_SCENARIO are:
# - only-blobs: proprietary rockchip ddrbin, miniloader and ATF
# - spl-blobs: proprietary rockchip ddrin and ATF, but uses mainline u-boot SPL in place of rockchip miniloader
# - tpl-spl-blob: uses mainline u-boot TPL and SPL with proprietary rockchip ATF blob
# - tpl-blob-atf-mainline: proprietary rockchip ddrbin + mainline u-boot SPL + mainline ATF
# - blobless: mainline u-boot TPL + mainline u-boot SPL + mainline ATF
# - binman:  u-boot builds full boot image from information in device tree.  See: https://docs.u-boot.org/en/latest/develop/package/binman.html

#BOOT_SOC=`expr $BOOTCONFIG : '.*\(rk[[:digit:]]\+.*\)_.*'`
BOOT_SOC=${BOOT_SOC:=$(expr $BOOTCONFIG : '.*\(rk[[:digit:]]\+.*\)_.*' || true)}

if [[ "a${BOOT_SOC}a" == "aa" ]]; then
	if [[ "${BOOTCONFIG}" != "" && "${BOOTCONFIG}" != " none" ]]; then # only warn if BOOTCONFIG set and not 'none'
		display_alert "Could not determine BOOT_SOC from BOOTCONFIG" "BOOTCONFIG: '${BOOTCONFIG}'" "warning"
	fi
else
	display_alert "Determined BOOT_SOC from BOOTCONFIG" "BOOT_SOC: '${BOOT_SOC}'; BOOTCONFIG: '${BOOTCONFIG}'" "info"
fi

CPUMIN=${CPUMIN:="408000"}

# BOOT_SOC_MKIMAGE defaults to BOOT_SOC, but can be overriden. See rk3566
declare -g BOOT_SOC_MKIMAGE="${BOOT_SOC}"

case "$BOOT_SOC" in
	rk3308)
		CPUMAX=${CPUMAX:="1296000"}
		BOOT_SCENARIO="${BOOT_SCENARIO:=only-blobs}"
		DDR_BLOB="${DDR_BLOB:-"rk33/rk3308_ddr_589MHz_uart2_m1_v1.30.bin"}"
		MINILOADER_BLOB="${MINILOADER_BLOB:-"rk33/rk3308_miniloader_v1.22.bin"}"
		BL31_BLOB="${BL31_BLOB:-"rk33/rk3308_bl31_v2.22.elf"}"
		;;

	rk3328)
		CPUMAX=${CPUMAX:="1296000"}
		BOOT_SCENARIO="${BOOT_SCENARIO:=only-blobs}"
		DDR_BLOB="${DDR_BLOB:-"rk33/rk3328_ddr_333MHz_v1.16.bin"}"
		MINILOADER_BLOB="${MINILOADER_BLOB:-"rk33/rk322xh_miniloader_v2.50.bin"}"
		BL31_BLOB="${BL31_BLOB:-"rk33/rk322xh_bl31_v1.44.elf"}"
		;;

	rk3399)
		CPUMAX=${CPUMAX:="2016000"}
		BOOT_SCENARIO="${BOOT_SCENARIO:=only-blobs}"
		DDR_BLOB="${DDR_BLOB:-"rk33/rk3399_ddr_933MHz_v1.25.bin"}"
		MINILOADER_BLOB="${MINILOADER_BLOB:-"rk33/rk3399_miniloader_v1.26.bin"}"
		BL31_BLOB="${BL31_BLOB:-"rk33/rk3399_bl31_v1.35.elf"}"
		;;

	rk3399pro)
		CPUMAX=${CPUMAX:="2016000"}
		BOOT_SCENARIO="${BOOT_SCENARIO:=only-blobs}"
		DDR_BLOB="${DDR_BLOB:-"rk33/rk3399pro_npu_ddr_933MHz_v1.02.bin"}"
		MINILOADER_BLOB="${MINILOADER_BLOB:-"rk33/rk3399pro_miniloader_v1.26.bin"}"
		BL31_BLOB="${BL31_BLOB:-"rk33/rk3399pro_bl31_v1.35.elf"}"
		;;

	rk3528)
		CPUMAX=${CPUMAX:="2016000"}
		BOOT_SCENARIO="${BOOT_SCENARIO:=spl-blobs}"
		DDR_BLOB="${DDR_BLOB:-"rk35/rk3528_ddr_1056MHz_v1.09.bin"}"
		BL31_BLOB="${BL31_BLOB:-"rk35/rk3528_bl31_v1.17.elf"}"
		;;

	rk3566)
		CPUMAX=${CPUMAX:="1800000"}
		BOOT_SCENARIO="${BOOT_SCENARIO:=spl-blobs}"
		DDR_BLOB="${DDR_BLOB:-"rk35/rk3566_ddr_1056MHz_v1.21.bin"}"
		BL31_BLOB="${BL31_BLOB:-"rk35/rk3568_bl31_v1.44.elf"}"
		# ROCKUSB_BLOB is used to flash a board with rkdeveloptool (Linux, can use 'rkdevflash' extension) or RKDevTool (Windows) in MASKROM mode
		ROCKUSB_BLOB="rk35/rk356x_spl_loader_v1.21.113.bin"
		BOOT_SOC_MKIMAGE="rk3568" # mkimage does not know about rk3566, and rk3568 works.
		BOOTENV_FILE='rk356x.txt'
		;;

	rk3568)
		CPUMAX=${CPUMAX:="1992000"}
		BOOT_SCENARIO="${BOOT_SCENARIO:=spl-blobs}"
		DDR_BLOB="${DDR_BLOB:-"rk35/rk3568_ddr_1560MHz_v1.21.bin"}"
		BL31_BLOB="${BL31_BLOB:-"rk35/rk3568_bl31_v1.44.elf"}"
		# ROCKUSB_BLOB is used to flash a board with rkdeveloptool (Linux, can use 'rkdevflash' extension) or RKDevTool (Windows) in MASKROM mode
		ROCKUSB_BLOB="rk35/rk356x_spl_loader_v1.21.113.bin"
		BOOTENV_FILE='rk356x.txt'
		;;

	rk3576)
		BOOT_SCENARIO="${BOOT_SCENARIO:=spl-blobs}"
		DDR_BLOB="${DDR_BLOB:-"rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.03.bin"}"
		BL31_BLOB="${BL31_BLOB:-"rk35/rk3576_bl31_v1.04.elf"}"
		BL32_BLOB="${BL32_BLOB:-"rk35/rk3576_bl32_v1.01.bin"}"
		;;

	rk3588) #CPUMAX undefined?
		BOOT_SCENARIO="${BOOT_SCENARIO:=spl-blobs}"
		DDR_BLOB="${DDR_BLOB:-"rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.16.bin"}"
		BL31_BLOB="${BL31_BLOB:-"rk35/rk3588_bl31_v1.45.elf"}"
		# ROCKUSB_BLOB is used to flash a board with rkdeveloptool (Linux, can use 'rkdevflash' extension) or RKDevTool (Windows) in MASKROM mode
		ROCKUSB_BLOB="rk35/rk3588_spl_loader_v1.16.113.bin"
		;;
esac

prepare_boot_configuration() {
	ATFSOURCE=''
	ATF_COMPILE='no'
	case "$BOOT_SCENARIO" in
		blobless | tpl-blob-atf-mainline)
			UBOOT_TARGET_MAP="BL31=bl31.elf idbloader.img u-boot.itb;;idbloader.img u-boot.itb"
			ATF_COMPILE=yes
			ATFSOURCE='https://github.com/ARM-software/arm-trusted-firmware'
			ATF_COMPILER='aarch64-linux-gnu-'
			ATFDIR='arm-trusted-firmware'
			ATFBRANCH='tag:lts-v2.8.8'
			ATF_USE_GCC='> 6.3'
			ATF_TARGET_MAP="M0_CROSS_COMPILE=arm-linux-gnueabi- PLAT=$BOOT_SOC bl31;;build/$BOOT_SOC/release/bl31/bl31.elf:bl31.elf"
			ATF_TOOLCHAIN2="arm-linux-gnueabi-:< 10.0"

			[[ $BOOT_SCENARIO == tpl-blob-atf-mainline ]] &&
				UBOOT_TARGET_MAP="BL31=bl31.elf idbloader.img u-boot.itb;;idbloader.img u-boot.itb"
			;;
		tpl-spl-blob)
			UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB idbloader.img u-boot.itb;;idbloader.img u-boot.itb"
			;;
		spl-blobs)
			UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB spl/u-boot-spl.bin u-boot.dtb u-boot.itb;;idbloader.img u-boot.itb"
			;;
		only-blobs)
			UBOOT_TARGET_MAP="u-boot-dtb.bin;;idbloader.bin uboot.img trust.bin"
			;;
		binman)
			UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"
			;;
	esac

	if [[ ! -z $BL32_BLOB ]]; then
		UBOOT_TARGET_MAP="BL32=$RKBIN_DIR/$BL32_BLOB ${UBOOT_TARGET_MAP}"
	fi

	if [[ $BOOT_SUPPORT_SPI == yes ]]; then

		if [[ "${BOOT_SPI_RKSPI_LOADER:-"no"}" != "yes" ]]; then
			UBOOT_TARGET_MAP="${UBOOT_TARGET_MAP} tpl/u-boot-tpl.bin spl/u-boot-spl.bin u-boot.itb rkspi_loader.img"
		else
			UBOOT_TARGET_MAP="${UBOOT_TARGET_MAP} rkspi_loader.img"
		fi

	fi
}

uboot_custom_postprocess() {
	[[ -z ${BOOT_SOC} ]] &&
		exit_with_error "BOOT_SOC not defined for scenario '${BOOT_SCENARIO}' for BOARD'=${BOARD}' and BOOTCONFIG='${BOOTCONFIG}'"
	display_alert "${BOARD}" "boots with ${BOOT_SCENARIO} scenario" "info"

	case "$BOOT_SCENARIO" in
		blobless | tpl-spl-blob | binman)
			:
			;;

		spl-blobs | tpl-blob-atf-mainline)
			# Bomb if DDR_BLOB not defined or does not exist
			declare SPL_BIN_PATH="${RKBIN_DIR}/${DDR_BLOB}"
			[[ -z ${SPL_BIN_PATH} ]] && exit_with_error "DDR_BLOB not defined for scenario ${BOOT_SCENARIO}"
			[[ ! -f "${SPL_BIN_PATH}" ]] && exit_with_error "DDR_BLOB ${SPL_BIN_PATH} does not exist for scenario ${BOOT_SCENARIO}"

			if [[ "$BOOT_SOC" == "rk3576" ]]; then
				display_alert "boot_merger for '${BOOT_SOC}' for scenario ${BOOT_SCENARIO}" "SPL_BIN_PATH: ${SPL_BIN_PATH}" "debug"
				RKBOOT_INI_FILE=rk3576.ini
				cp $RKBIN_DIR/rk35/RK3576MINIALL.ini $RKBOOT_INI_FILE
				sed -i "s|FlashBoost=.*$|FlashBoost=${RKBIN_DIR}/rk35/rk3576_boost_v1.02.bin|g" $RKBOOT_INI_FILE
				sed -i "s|Path1=.*rk3576_ddr.*$|Path1=${SPL_BIN_PATH}|g" $RKBOOT_INI_FILE
				sed -i "s|Path1=.*rk3576_usbplug.*$|Path1=${RKBIN_DIR}/rk35/rk3576_usbplug_v1.03.bin|g" $RKBOOT_INI_FILE
				sed -i "s|FlashData=.*$|FlashData=${SPL_BIN_PATH}|g" $RKBOOT_INI_FILE
				sed -i "s|FlashBoot=.*$|FlashBoot=./spl/u-boot-spl.bin|g" $RKBOOT_INI_FILE
				sed -i "s|IDB_PATH=.*$|IDB_PATH=idbloader.img|g" $RKBOOT_INI_FILE
				run_host_x86_binary_logged $RKBIN_DIR/tools/boot_merger $RKBOOT_INI_FILE
				rm -f $RKBOOT_INI_FILE
			else
				display_alert "mkimage for '${BOOT_SOC}' for scenario ${BOOT_SCENARIO}" "SPL_BIN_PATH: ${SPL_BIN_PATH}" "debug"
				run_host_command_logged tools/mkimage -n "${BOOT_SOC_MKIMAGE}" -T rksd -d "${SPL_BIN_PATH}:spl/u-boot-spl.bin" idbloader.img
			fi
			;;

		only-blobs)
			local tempfile
			tempfile=$(mktemp)
			run_host_command_logged tools/mkimage -n "${BOOT_SOC_MKIMAGE}" -T rksd -d $RKBIN_DIR/$DDR_BLOB idbloader.bin
			cat $RKBIN_DIR/$MINILOADER_BLOB >> idbloader.bin
			run_host_x86_binary_logged $RKBIN_DIR/tools/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x200000
			run_host_x86_binary_logged $RKBIN_DIR/tools/trust_merger --replace bl31.elf $RKBIN_DIR/$BL31_BLOB trust.ini
			;;

		*)
			exit_with_error "\"$BOOT_SCENARIO\" is an Unsupported Boot Scenario!"
			;;
	esac

	if [[ $BOOT_SUPPORT_SPI == yes ]]; then
		if [[ "${BOOT_SPI_RKSPI_LOADER:-"no"}" == "yes" ]]; then
			dd if=/dev/zero of=rkspi_loader.img bs=1M count=0 seek=16
			/sbin/parted -s rkspi_loader.img mklabel gpt
			/sbin/parted -s rkspi_loader.img unit s mkpart idbloader 64 7167
			/sbin/parted -s rkspi_loader.img unit s mkpart vnvm 7168 7679
			/sbin/parted -s rkspi_loader.img unit s mkpart reserved_space 7680 8063
			/sbin/parted -s rkspi_loader.img unit s mkpart reserved1 8064 8127
			/sbin/parted -s rkspi_loader.img unit s mkpart uboot_env 8128 8191
			/sbin/parted -s rkspi_loader.img unit s mkpart reserved2 8192 16383
			/sbin/parted -s rkspi_loader.img unit s mkpart uboot 16384 32734
			dd if=idbloader.img of=rkspi_loader.img seek=64 conv=notrunc
			dd if=u-boot.itb of=rkspi_loader.img seek=16384 conv=notrunc
		else
			tools/mkimage -n "${BOOT_SOC_MKIMAGE}" -T rkspi -d tpl/u-boot-tpl.bin:spl/u-boot-spl.bin rkspi_tpl_spl.img
			dd if=/dev/zero of=rkspi_loader.img count=8128 status=none
			dd if=rkspi_tpl_spl.img of=rkspi_loader.img conv=notrunc status=none
			dd if=u-boot.itb of=rkspi_loader.img seek=768 conv=notrunc status=none
		fi
	fi
}

write_uboot_platform() {
	# This is run board-side too, so account for the non-existance of run_host_command_logged
	local logging_prelude=""
	[[ $(type -t run_host_command_logged) == function ]] && logging_prelude="run_host_command_logged"

	if [ -f $1/u-boot-rockchip.bin ]; then #"$BOOT_SCENARIO" == binman
		${logging_prelude} dd if=$1/u-boot-rockchip.bin of=$2 bs=32k seek=1 conv=notrunc status=none
	elif [ -f $1/rksd_loader.img ]; then # legacy rk3399 loader
		${logging_prelude} dd if=$1/rksd_loader.img of=$2 seek=64 conv=notrunc status=none
	elif [[ -f $1/u-boot.itb ]]; then # $BOOT_SCENARIO "blobless" or "tpl-spl-blob"
		${logging_prelude} dd if=$1/idbloader.img of=$2 seek=64 conv=notrunc status=none
		${logging_prelude} dd if=$1/u-boot.itb of=$2 seek=16384 conv=notrunc status=none
	elif [[ -f $1/uboot.img ]]; then # $BOOT_SCENARIO == "only-blobs"
		${logging_prelude} dd if=$1/idbloader.bin of=$2 seek=64 conv=notrunc status=none
		${logging_prelude} dd if=$1/uboot.img of=$2 seek=16384 conv=notrunc status=none
		${logging_prelude} dd if=$1/trust.bin of=$2 seek=24576 conv=notrunc status=none
	else
		echo "Unsupported u-boot processing configuration!"
		exit 1
	fi
}

# @TODO: this is not ready for BOOT_SCENARIO=binman yet
write_uboot_platform_mtd() {
	if [[ -f $1/rkspi_loader.img ]]; then
		dd if=$1/rkspi_loader.img of=$2 conv=notrunc status=none > /dev/null 2>&1
	else
		echo "SPI u-boot image not found!"
		exit 1
	fi
}

setup_write_uboot_platform() {

	if grep -q "ubootpart" /proc/cmdline; then

		local tmp=$(cat /proc/cmdline)
		tmp="${tmp##*ubootpart=}"
		tmp="${tmp%% *}"
		[[ -n $tmp ]] && local part=$(findfs PARTUUID=$tmp 2> /dev/null)
		[[ -n $part ]] && local dev=$(lsblk -n -o PKNAME $part 2> /dev/null)
		[[ -n $dev ]] && DEVICE="/dev/$dev"

	fi

}

family_tweaks() {

	if [[ -f $SDCARD/lib/systemd/system/rk3399-bluetooth.service ]]; then

		# install and enable Bluetooth
		chroot_sdcard_apt_get_install rfkill bluetooth bluez bluez-tools
		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable rk3399-bluetooth.service >/dev/null 2>&1"

	elif [[ -f $SDCARD/lib/systemd/system/sprd-bluetooth.service ]]; then

		# install and enable Bluetooth
		chroot_sdcard_apt_get_install rfkill bluetooth bluez bluez-tools
		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable sprd-bluetooth.service >/dev/null 2>&1"

	fi

}

family_tweaks_bsp() {

	if [[ $BOOTCONFIG == *3328* ]] && [[ $BRANCH != legacy ]]; then
		mkdir -p "$destination"/etc/X11/xorg.conf.d
		cat <<- EOF > "$destination"/etc/X11/xorg.conf.d/02-driver.conf
			# set fbdev as default driver.
			Section "Device"
			         Identifier "NOGPU"
			         Driver "fbdev"
			EndSection
		EOF
	fi

	# Graphics and media
	mkdir -p $destination/etc/udev/rules.d
	cp $SRC/packages/bsp/rk3399/50-mali.rules $destination/etc/udev/rules.d/
	cp $SRC/packages/bsp/rk3399/50-rk3399-vpu.rules $destination/etc/udev/rules.d/
	mkdir -p $destination/etc/sysfs.d
	cp $SRC/packages/bsp/rk3399/20-gpu-governor.conf $destination/etc/sysfs.d/

}

# A late hook to default SERIALCON based on BRANCH; BOARD and hooks (earlier than 900) can set it to override this.
function post_family_config__900_late_default_serial_console_by_branch() {
	display_alert "rockchip64_common: defaulting SERIALCON" "initial SERIALCON: '${SERIALCON:-"unset"}'" "debug"

	# If already set (by BOARD or hooks/extensions ran before this), keep it.
	if [[ -n $SERIALCON ]]; then
		display_alert "rockchip64_common: defaulting SERIALCON" "SERIALCON already set to '${SERIALCON}', keeping it." "info"
		return 0
	fi

	case $BRANCH in
		legacy | vendor)
			display_alert "rockchip64_common: defaulting SERIALCON" "Setting SERIALCON to ttyFIQ0 for BRANCH='${BRANCH}'" "info"
			SERIALCON="ttyFIQ0"
			;;
		*)
			display_alert "rockchip64_common: defaulting SERIALCON" "Setting SERIALCON to ttyS2 for BRANCH='${BRANCH}'" "info"
			SERIALCON="ttyS2"
			;;
	esac

	display_alert "rockchip64_common: defaulting SERIALCON" "final SERIALCON: '${SERIALCON}' for BRANCH='${BRANCH}'" "debug"
}
