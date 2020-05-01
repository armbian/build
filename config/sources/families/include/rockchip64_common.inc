ARCH=arm64
KERNEL_IMAGE_TYPE=Image
OFFSET=16
BOOTSCRIPT='boot-rockchip64.cmd:boot.cmd'
BOOTENV_FILE='rockchip-default.txt'
UBOOT_TARGET_MAP=";;idbloader.bin uboot.img trust.bin"
BOOTDELAY=0
OVERLAY_PREFIX='rockchip'
SERIALCON=${SERIALCON:-'ttyFIQ0:1500000'}
GOVERNOR="ondemand"
CPUMAX="2016000"
CPUMIN="600000"

RKBIN_DIR="$SRC/cache/sources/rkbin-tools"

if [[ $BOOTCONFIG == *3328* ]]; then

	BOOT_RK3328_USE_AYUFAN_ATF=yes
	CPUMAX="1390000"

elif [[ $BOARD == rockpi-4* ]]; then

	BOOT_USE_TPL_SPL_BLOB=yes
	BL31_BLOB='rk33/rk3399_bl31_v1.30.elf'

elif [[ $BOARD == rockpro64 ]] || [[ $BOARD == pinebook-pro ]]; then

	BOOT_RK3399_LEGACY_HYBRID=yes

elif [[ $BOARD == rockpi-s ]]; then

	UBOOT_TARGET_MAP="u-boot-dtb.bin;;idbloader.bin uboot.img trust.bin"
	CPUMAX="1296000"

else

	ATFPATCHDIR='atf-rk3399'

fi

case $BRANCH in

	current)

		KERNELPATCHDIR='rockchip64-'$BRANCH
		KERNELBRANCH="branch:linux-5.4.y"
		LINUXFAMILY=rockchip64
		LINUXCONFIG='linux-rockchip64-'$BRANCH

	;;

	dev)

		KERNELPATCHDIR='rockchip64-'$BRANCH
		KERNELBRANCH="branch:linux-5.6.y"
		LINUXFAMILY=rockchip64
		LINUXCONFIG='linux-rockchip64-'$BRANCH

	;;

esac

prepare_boot_configuration()
{
	if [[ $BOOT_USE_MAINLINE_ATF == yes ]]; then

		UBOOT_TARGET_MAP="BL31=bl31.bin idbloader.img u-boot.itb;;idbloader.img u-boot.itb"
		ATFSOURCE='https://github.com/ARM-software/arm-trusted-firmware'
		ATFDIR='arm-trusted-firmware'
		ATFBRANCH='tag:v2.2'
		ATF_USE_GCC='> 6.3'
		ATF_TARGET_MAP='M0_CROSS_COMPILE=arm-linux-gnueabi- PLAT=rk3399 bl31;;build/rk3399/release/bl31/bl31.elf:bl31.bin'
		ATF_TOOLCHAIN2="arm-linux-gnueabi-:> 5.0"

	elif [[ $BOOT_USE_TPL_SPL_BLOB == yes ]]; then

		UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB idbloader.img u-boot.itb;;idbloader.img u-boot.itb"
		ATFSOURCE=''
		ATF_COMPILE='no'

	elif [[ $BOOT_USE_BLOBS == yes ]]; then

		UBOOT_TARGET_MAP="u-boot-dtb.bin;;idbloader.bin uboot.img trust.bin"
		ATFSOURCE=''
		ATF_COMPILE='no'

	elif [[ $BOOT_RK3399_LEGACY_HYBRID == yes ]]; then # to be removed

		UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB u-boot-dtb.bin spl/u-boot-spl.bin u-boot.itb;;spl/u-boot-spl.bin u-boot.itb"
		ATFSOURCE=''
		ATF_COMPILE='no'

		legacy_uboot_locations

	elif [[ $BOOT_RK3328_USE_AYUFAN_ATF == yes ]]; then # to be removed

		UBOOT_TARGET_MAP=";;idbloader.bin uboot.img trust.bin"
		ATFSOURCE='https://github.com/ayufan-rock64/arm-trusted-firmware'
		ATFDIR='arm-trusted-firmware-rockchip64'
		ATFBRANCH='branch:rockchip'
		ATF_USE_GCC='> 6.3'
		ATF_TARGET_MAP='PLAT=rk322xh DEBUG=1 bl31;;trust.bin'
		ATF_TOOLCHAIN2="arm-linux-gnueabi-:> 5.0"

		legacy_uboot_locations

	fi
}

legacy_uboot_locations()
{
	BOOTSOURCE='https://github.com/ayufan-rock64/linux-u-boot'
	BOOTDIR='u-boot-rockchip64'
	BOOTBRANCH='branch:rockchip-master'
	case $BRANCH in
		legacy)
			BOOTPATCHDIR="u-boot-rockchip64"
			;;
		*)
			BOOTPATCHDIR="u-boot-rockchip64-dev"
			;;
	esac
}

uboot_custom_postprocess()
{
	if [[ $BOOT_USE_MAINLINE_ATF == yes || $BOOT_USE_TPL_SPL_BLOB == yes ]]; then

		:

	elif [[ $BOOT_USE_BLOBS == yes ]]; then

		local tempfile=$(mktemp)
		tools/mkimage -n $BOOT_SOC -T rksd -d $RKBIN_DIR/$DDR_BLOB idbloader.bin
		cat $RKBIN_DIR/$MINILOADER_BLOB >> idbloader.bin
		loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x200000
		trust_merger --replace ./build/rk3399/debug/bl31/bl31.elf $RKBIN_DIR/$BL31_BLOB trust.ini

	elif [[ $BOOT_RK3399_LEGACY_HYBRID == yes ]]; then

		# 3399
		tools/mkimage -n rk3399 -T rksd -d $SRC/cache/sources/rkbin-tools/rk33/rk3399_ddr_933MHz_v1.13.bin rksd_loader.img
		cat spl/u-boot-spl.bin >> rksd_loader.img
		dd if=u-boot.itb of=rksd_loader.img seek=448 conv=notrunc
		cp rksd_loader.img $SRC/.tmp/$uboot_name/usr/lib/$uboot_name/$f_dst
		tools/mkimage -n rk3399 -T rksd -d $SRC/cache/sources/rkbin-tools/rk33/rk3399_ddr_933MHz_v1.13.bin rkspi_loader.img
		cat spl/u-boot-spl.bin >> rkspi_loader.img
		for i in `seq 1 128`; do dd count=4 status=none; dd if=/dev/zero count=4 status=none; done < rkspi_loader.img > rkspi_loader.tmp
		mv rkspi_loader.tmp rkspi_loader.img
		dd if=u-boot.itb of=rkspi_loader.img seek=1024 conv=notrunc
		cp rkspi_loader.img $SRC/.tmp/$uboot_name/usr/lib/$uboot_name/$f_dst

	elif [[ $BOOT_RK3328_USE_AYUFAN_ATF == yes ]]; then

		# 3328
		tools/mkimage -n rk3328 -T rksd -d $SRC/cache/sources/rkbin-tools/rk33/rk3328_ddr_786MHz_v1.13.bin idbloader.bin
		cat $SRC/cache/sources/rkbin-tools/rk33/rk3328_miniloader_v2.46.bin >> idbloader.bin
		loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x200000

	else
		echo "Unsupported u-boot processing configuration!"
		exit 1
	fi
}

write_uboot_platform()
{
	if [[ -f $1/u-boot.itb ]]; then # $BOOT_USE_MAINLINE_ATF == yes || $BOOT_USE_TPL_SPL_BLOB == yes

		dd if=$1/idbloader.img of=$2 seek=64 conv=notrunc status=none >/dev/null 2>&1
		dd if=$1/u-boot.itb of=$2 seek=16384 conv=notrunc status=none >/dev/null 2>&1

	elif [[ -f $1/uboot.img ]]; then # $BOOT_USE_BLOBS == yes

		dd if=$1/idbloader.bin of=$2 seek=64 conv=notrunc status=none >/dev/null 2>&1
		dd if=$1/uboot.img of=$2 seek=16384 conv=notrunc status=none >/dev/null 2>&1
		dd if=$1/trust.bin of=$2 seek=24576 conv=notrunc status=none >/dev/null 2>&1

	elif [[ -f $1/rksd_loader.img ]] ; then # legacy rk3399 loader

		dd if=$1/rksd_loader.img of=$2 seek=64 conv=notrunc status=none >/dev/null 2>&1

	else
		echo "Unsupported u-boot processing configuration!"
		exit 1

	fi
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

	fi

}


atf_custom_postprocess()
{

	# remove bl31.bin which can be 4+GiB in size and thus may fill the tmpfs mount
	rm -f build/rk322xh/debug/bl31.bin
	# ATF
	trust_merger trust.ini

}


family_tweaks()
{

	if [[ $BOARD == z28pro ]]; then

		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable z28pro-bluetooth.service >/dev/null 2>&1"

	elif [[ $BOARD == nanopi-r2s ]]; then

		# rename USB based network to lan0
		mkdir -p $SDCARD/etc/udev/rules.d/
		echo 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="r8152", KERNEL=="eth1", NAME="lan0"' > $SDCARD/etc/udev/rules.d/70-rename-lan.rules

		# workaround - create old school initial network config since network manager have issues
		echo "auto eth0" >> $SDCARD/etc/network/interfaces
		echo "	iface eth0 inet dhcp" >> $SDCARD/etc/network/interfaces
		echo "auto lan0" >> $SDCARD/etc/network/interfaces
		echo "	iface lan0 inet dhcp" >> $SDCARD/etc/network/interfaces

	elif [[ -f $SDCARD/lib/systemd/system/rk3399-bluetooth.service ]]; then

		# install and enable Bluetooth
		chroot $SDCARD /bin/bash -c "apt-get -y -qq install rfkill bluetooth bluez bluez-tools"
		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable rk3399-bluetooth.service >/dev/null 2>&1"

	fi

	if [[ $BOARD == nanopim4v2 ]]; then
		mv $SDCARD/lib/firmware/brcm/brcmfmac4356-sdio.bin{,.bak}
		ln -s brcmfmac4356-sdio-nanopi-m4v2.bin $SDCARD/lib/firmware/brcm/brcmfmac4356-sdio.bin
		ln -s brcmfmac4356-sdio-nanopi-m4v2.txt $SDCARD/lib/firmware/brcm/brcmfmac4356-sdio.friendlyarm,nanopi-m4.txt
	fi

}


family_tweaks_bsp()
{

	if [[ $BOARD == z28pro ]]; then

		mkdir -p $destination/usr/local/bin

		# Bluetooth for Z28 PRO
		install -m 755 $SRC/packages/bsp/rk3328/z28pro/8822b_hciattach $destination/usr/bin
		install -m 755 $SRC/packages/bsp/rk3328/z28pro/start_bt.sh $destination/usr/local/bin
		cp $SRC/packages/bsp/rk3328/z28pro/z28pro-bluetooth.service $destination/lib/systemd/system/

	elif [[ $BOARD == rockpi-4b || $BOARD == nanop* || $BOARD == orangepi* || $BOARD == firefly* || $BOARD == roc-rk3399-pc ]]; then

		# Bluetooth for most of others
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	if [[ $BOARD == pinebook-pro ]]; then

		cp $SRC/packages/bsp/pinebook-pro/xorg.conf $destination/etc/X11/
	fi

	# Graphics and media
	mkdir -p $destination/etc/udev/rules.d
	cp $SRC/packages/bsp/rk3399/50-mali.rules $destination/etc/udev/rules.d/
	cp $SRC/packages/bsp/rk3399/50-rk3399-vpu.rules $destination/etc/udev/rules.d/
	mkdir -p $destination/etc/sysfs.d
	cp $SRC/packages/bsp/rk3399/20-gpu-governor.conf $destination/etc/sysfs.d/

}
