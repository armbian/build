ARCH=arm64
KERNEL_IMAGE_TYPE=Image
OFFSET=16
BOOTSCRIPT='boot-rockchip64.cmd:boot.cmd'
BOOTENV_FILE='rockchip-default.txt'
UBOOT_TARGET_MAP=";;idbloader.bin uboot.img trust.bin"
BOOTDELAY=0
OVERLAY_PREFIX='rockchip'
SERIALCON='ttyFIQ0:1500000'
ATFSOURCE='https://github.com/ayufan-rock64/arm-trusted-firmware'
ATF_TARGET_MAP='M0_CROSS_COMPILE=arm-linux-gnueabi- PLAT=rk3399 DEBUG=1 bl31;;trust.bin'
ATF_TOOLCHAIN2="arm-linux-gnueabi-:> 5.0"
ATFDIR='arm-trusted-firmware-rockchip64'
ATFBRANCH='branch:rockchip'
ATF_USE_GCC='> 6.3'
GOVERNOR="ondemand"
CPUMAX="2016000"
CPUMIN="600000"

if [[ $BOOTCONFIG == *3328* ]]; then

	ATF_TARGET_MAP='PLAT=rk322xh DEBUG=1 bl31;;trust.bin'
	CPUMAX="1390000"

elif [[ $BOARD == rockpro64 ]] || [[ $BOARD == rockpi-4* ]]; then

	UBOOT_TARGET_MAP="BL31=$SRC/cache/sources/rkbin-tools/rk33/rk3399_bl31_v1.17.elf u-boot-dtb.bin spl/u-boot-spl.bin u-boot.itb;;spl/u-boot-spl.bin u-boot.itb"

elif [[ $BOARD == rockpi-s ]]; then

	UBOOT_TARGET_MAP="u-boot-dtb.bin;;idbloader.bin uboot.img trust.bin"
	CPUMAX="1296000"

else

	ATFPATCHDIR='atf-rk3399'

fi

case $BRANCH in

	current)
		
		KERNELSOURCE='https://gitlab.manjaro.org/tsys/linux-pinebook-pro.git'
		KERNELPATCHDIR='rockchip64-'$BRANCH
		KERNELBRANCH="branch:v5.5"
		LINUXFAMILY=rockchip64
		LINUXCONFIG='linux-rockchip64-'$BRANCH

	;;

	dev)

		KERNELSOURCE='https://github.com/ayufan-rock64/linux-mainline-kernel'
		KERNELBRANCH='tag:5.4.0-rc1-1120-ayufan'
		KERNELDIR='linux-rockchip64'
		KERNELPATCHDIR='rockchip64-'$BRANCH
		LINUXFAMILY=rockchip64
		LINUXCONFIG='linux-rockchip64-'$BRANCH

	;;

esac


write_uboot_platform()
{

	if [[ -f $1/rksd_loader.img ]] ; then
		dd if=$1/rksd_loader.img of=$2 seek=64 conv=notrunc status=none >/dev/null 2>&1
	else
		dd if=$1/idbloader.bin of=$2 seek=64 conv=notrunc status=none >/dev/null 2>&1
		dd if=$1/uboot.img of=$2 seek=16384 conv=notrunc status=none >/dev/null 2>&1
		dd if=$1/trust.bin of=$2 seek=24576 conv=notrunc status=none >/dev/null 2>&1
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

	[[ $BOARD == firefly-rk3399 ]] && echo "fdtfile=rockchip/rk3399-firefly.dtb" >> $SDCARD/boot/armbianEnv.txt
	[[ $BOARD == nanopct4 ]] && echo "fdtfile=rockchip/rk3399-nanopc-t4.dtb" >> $SDCARD/boot/armbianEnv.txt
	[[ $BOARD == nanopim4 ]] && echo "fdtfile=rockchip/rk3399-nanopi-m4.dtb" >> $SDCARD/boot/armbianEnv.txt
	[[ $BOARD == nanopim4v2 ]] && echo "fdtfile=rockchip/rk3399-nanopi-m4v2.dtb" >> $SDCARD/boot/armbianEnv.txt
	[[ $BOARD == nanopineo4 ]] && echo "fdtfile=rockchip/rk3399-nanopi-neo4.dtb" >> $SDCARD/boot/armbianEnv.txt
	[[ $BOARD == orangepi-rk3399 ]] && echo "fdtfile=rockchip/rk3399-orangepi.dtb" >> $SDCARD/boot/armbianEnv.txt
	[[ $BOARD == pinebook-pro ]] && echo "fdtfile=rockchip/rk3399-pinebook-pro.dtb" >> $SDCARD/boot/armbianEnv.txt
	[[ $BOARD == roc-rk3399-pc ]] && echo "fdtfile=rockchip/rk3399-roc-pc.dtb" >> $SDCARD/boot/armbianEnv.txt
	[[ $BOARD == rockpi-4* ]] && echo "fdtfile=rockchip/rk3399-rock-pi-4.dtb" >> $SDCARD/boot/armbianEnv.txt

	if [[ $BOARD == z28pro ]]; then

		echo "fdtfile=rockchip/rk3328-z28pro.dtb" >> $SDCARD/boot/armbianEnv.txt
		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable z28pro-bluetooth.service >/dev/null 2>&1"

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
