enable_extension "rkbin-tools"
ARCH=arm64
KERNEL_IMAGE_TYPE=Image
OFFSET=16
BOOTSCRIPT='boot-rockchip64.cmd:boot.cmd'
BOOTENV_FILE='rockchip64.txt'
UBOOT_TARGET_MAP=";;idbloader.bin uboot.img trust.bin"
BOOTDELAY=0
OVERLAY_PREFIX='rockchip'
SERIALCON=${SERIALCON:=$([ $BRANCH == "legacy" ] && echo "ttyFIQ0:1500000" || echo "ttyS2:1500000")}
GOVERNOR="ondemand"
ATFPATCHDIR='atf-rockchip64'
BOOTBRANCH="tag:v2022.04"
BOOTPATCHDIR="u-boot-rockchip64"
PACKAGE_LIST_FAMILY="ethtool"

RKBIN_DIR="$SRC/cache/sources/rkbin-tools"

BOOT_SOC=${BOOT_SOC:=$(expr $BOOTCONFIG : '.*\(rk[[:digit:]]\+.*\)_.*')}
display_alert "BOOT_SOC:" "$BOOT_SOC" "debug"

CPUMIN=${CPUMIN:="408000"}

if [[ $BOOT_SOC == rk3399 ]]; then

	CPUMAX=${CPUMAX:="2016000"}

elif [[ $BOOT_SOC == rk3328 || $BOOT_SOC == rk3308 ]]; then

	CPUMAX=${CPUMAX:="1296000"}

elif [[ "${BOOT_SOC}" == rk3566 ]]; then

	CPUMAX=${CPUMAX:="1800000"}

elif [[ "${BOOT_SOC}" == rk3568 ]]; then

	CPUMAX=${CPUMAX:="1992000"}

fi

if [[ $BOOT_SOC == rk3328 ]]; then

	BOOT_SCENARIO="${BOOT_SCENARIO:=only-blobs}"
	DDR_BLOB='rk33/rk3328_ddr_333MHz_v1.16.bin'
	MINILOADER_BLOB='rk33/rk322xh_miniloader_v2.50.bin'
	BL31_BLOB='rk33/rk322xh_bl31_v1.44.elf'

elif [[ $BOOT_SOC == rk3399 ]]; then

	BOOT_SCENARIO="${BOOT_SCENARIO:=only-blobs}"
	DDR_BLOB='rk33/rk3399_ddr_933MHz_v1.25.bin'
	MINILOADER_BLOB='rk33/rk3399_miniloader_v1.26.bin'
	BL31_BLOB='rk33/rk3399_bl31_v1.35.elf'

elif [[ $BOOT_SOC == rk3399pro ]]; then

	BOOT_SCENARIO="${BOOT_SCENARIO:=only-blobs}"
	DDR_BLOB='rk33/rk3399pro_npu_ddr_933MHz_v1.02.bin'
	MINILOADER_BLOB='rk33/rk3399pro_miniloader_v1.26.bin'
	BL31_BLOB='rk33/rk3399pro_bl31_v1.35.elf'

elif [[ $BOOT_SOC == rk3566 ]]; then

	BOOT_SCENARIO="${BOOT_SCENARIO:=spl-blobs}"
	DDR_BLOB='rk35/rk3566_ddr_1056MHz_v1.10.bin'
	BL31_BLOB='rk35/rk3568_bl31_v1.29.elf'

elif [[ $BOOT_SOC == rk3568 ]]; then

	BOOT_SCENARIO="${BOOT_SCENARIO:=spl-blobs}"
	DDR_BLOB="${DDR_BLOB:-"rk35/rk3568_ddr_1560MHz_v1.10.bin"}"
	BL31_BLOB="${BL31_BLOB:-"rk35/rk3568_bl31_v1.28.elf"}"
	display_alert "BOOT_SCENARIO:" "$BOOT_SCENARIO" "debug"
	display_alert "DDR_BLOB:" "$DDR_BLOB" "debug"
	display_alert "BL31_BLOB:" "$BL31_BLOB" "debug"

elif [[ $BOARD == rockpi-s ]]; then

	BOOT_SCENARIO="${BOOT_SCENARIO:=only-blobs}"
	BOOT_SOC=rk3308
	DDR_BLOB='rk33/rk3308_ddr_589MHz_uart2_m1_v1.30.bin'
	MINILOADER_BLOB='rk33/rk3308_miniloader_v1.22.bin'
	BL31_BLOB='rk33/rk3308_bl31_v2.22.elf'

	if [[ ${BRANCH} == legacy ]]; then
		DDR_BLOB='rk33/rk3308_ddr_589MHz_uart2_m0_v1.26.bin'
		MINILOADER_BLOB='rk33/rk3308_miniloader_sd_nand_v1.13.bin'
		BL31_BLOB='rk33/rk3308_bl31_v2.10.elf'
	fi
fi

case $BRANCH in

	current)

		export KERNEL_MAJOR_MINOR="5.15" # Major and minor versions of this kernel.
		KERNELBRANCH="branch:linux-5.15.y"
		KERNELPATCHDIR='rockchip64-'$BRANCH
		LINUXFAMILY=rockchip64
		LINUXCONFIG='linux-rockchip64-'$BRANCH
		;;

	edge)

		KERNELPATCHDIR='rockchip64-'$BRANCH
		export KERNEL_MAJOR_MINOR="5.18" # Major and minor versions of this kernel.
		KERNELBRANCH="branch:linux-5.18.y"
		LINUXFAMILY=rockchip64
		LINUXCONFIG='linux-rockchip64-'$BRANCH

		;;

esac

prepare_boot_configuration() {
	if [[ $BOOT_SCENARIO == "blobless" ]]; then

		UBOOT_TARGET_MAP="BL31=bl31.bin idbloader.img u-boot.itb;;idbloader.img u-boot.itb"
		ATFSOURCE='https://github.com/ARM-software/arm-trusted-firmware'
		ATF_COMPILER='aarch64-linux-gnu-'
		ATFDIR='arm-trusted-firmware'
		ATFBRANCH='tag:v2.6'
		ATF_USE_GCC='> 6.3'
		ATF_TARGET_MAP="M0_CROSS_COMPILE=arm-linux-gnueabi- PLAT=$BOOT_SOC bl31;;build/$BOOT_SOC/release/bl31/bl31.elf:bl31.bin"
		ATF_TOOLCHAIN2="arm-linux-gnueabi-:> 5.0"

	elif [[ $BOOT_SCENARIO == "tpl-spl-blob" ]]; then

		UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB idbloader.img u-boot.itb;;idbloader.img u-boot.itb"
		ATFSOURCE=''
		ATF_COMPILE='no'

	elif [[ $BOOT_SCENARIO == "spl-blobs" ]]; then

		display_alert "BOOT Scenario is" "spl-blobs" "debug"
		UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB spl/u-boot-spl.bin u-boot.dtb u-boot.itb;;idbloader.img u-boot.itb"
		ATFSOURCE=''
		ATF_COMPILE='no'

	elif [[ $BOOT_SCENARIO == "only-blobs" ]]; then

		UBOOT_TARGET_MAP="u-boot-dtb.bin;;idbloader.bin uboot.img trust.bin"
		ATFSOURCE=''
		ATF_COMPILE='no'

	fi

	if [[ $BOOT_SUPPORT_SPI == yes ]]; then

		UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB tpl/u-boot-tpl.bin spl/u-boot-spl.bin u-boot.itb ${UBOOT_TARGET_MAP} rkspi_loader.img"

	fi
}

uboot_custom_postprocess() {

	if [[ $BOOT_SCENARIO == "blobless" || $BOOT_SCENARIO == "tpl-spl-blob" ]]; then
		:
	elif [[ $BOOT_SCENARIO == "spl-blobs" ]]; then
		display_alert "mkimage for $BOOT_SOC with $BOOT_SCENARIO" "spl-blobs" "debug"
		run_host_command_logged tools/mkimage -n $BOOT_SOC -T rksd -d $RKBIN_DIR/$DDR_BLOB:spl/u-boot-spl.bin idbloader.img

	elif [[ $BOOT_SCENARIO == "only-blobs" ]]; then

		local tempfile=$(mktemp)
		run_host_command_logged tools/mkimage -n $BOOT_SOC -T rksd -d $RKBIN_DIR/$DDR_BLOB idbloader.bin
		cat $RKBIN_DIR/$MINILOADER_BLOB >> idbloader.bin
		run_host_x86_binary_logged $RKBIN_DIR/tools/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x200000
		run_host_x86_binary_logged $RKBIN_DIR/tools/trust_merger --replace bl31.elf $RKBIN_DIR/$BL31_BLOB trust.ini

	else
		echo "Unsupported u-boot processing configuration!"
		exit 1
	fi

	if [[ $BOOT_SUPPORT_SPI == yes ]]; then
		tools/mkimage -n $BOOT_SOC -T rkspi -d tpl/u-boot-tpl.bin:spl/u-boot-spl.bin rkspi_tpl_spl.img
		dd if=/dev/zero of=rkspi_loader.img count=8128 status=none
		dd if=rkspi_tpl_spl.img of=rkspi_loader.img conv=notrunc status=none
		dd if=u-boot.itb of=rkspi_loader.img seek=768 conv=notrunc status=none
	fi
}

write_uboot_platform() {
	# This is run board-side too, so account for the non-existance of run_host_command_logged
	local logging_prelude=""
	[[ $(type -t run_host_command_logged) == function ]] && logging_prelude="run_host_command_logged"

	if [[ -f $1/rksd_loader.img ]]; then # legacy rk3399 loader
		${logging_prelude} dd if=$1/rksd_loader.img of=$2 seek=64 conv=notrunc status=none
	elif [[ -f $1/u-boot.itb ]]; then # $BOOT_SCENARIO == "blobless" || $BOOT_SCENARIO == "tpl-spl-blob"
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

	if [[ $BOARD == z28pro ]]; then

		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable z28pro-bluetooth.service >/dev/null 2>&1"

	elif [[ $BOARD == nanopi-r2s || $BOARD == nanopi-r2c || $BOARD == orangepi-r1plus || $BOARD == orangepi-r1plus-lts ]]; then

		# rename USB based network to lan0
		mkdir -p $SDCARD/etc/udev/rules.d/
		echo 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="r8152", KERNEL=="eth1", NAME="lan0"' > $SDCARD/etc/udev/rules.d/70-rename-lan.rules

	elif [[ $BOARD == helios64 ]]; then

		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable helios64-heartbeat-led.service >/dev/null 2>&1"

	elif [[ -f $SDCARD/lib/systemd/system/rk3399-bluetooth.service ]]; then

		# install and enable Bluetooth
		chroot $SDCARD /bin/bash -c "apt-get -y -qq install rfkill bluetooth bluez bluez-tools"
		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable rk3399-bluetooth.service >/dev/null 2>&1"

	elif [[ -f $SDCARD/lib/systemd/system/sprd-bluetooth.service ]]; then

		# install and enable Bluetooth
		chroot $SDCARD /bin/bash -c "apt-get -y -qq install rfkill bluetooth bluez bluez-tools"
		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable sprd-bluetooth.service >/dev/null 2>&1"

	fi

	if [[ $BOARD == nanopim4* ]]; then

		# enable fan support
		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable nanopim4-pwm-fan.service >/dev/null 2>&1"

	fi

	if [[ $BOARD == pinebook-pro ]]; then

		chroot $SDCARD /bin/bash -c "echo SuspendState=freeze >> /etc/systemd/sleep.conf"
		chroot $SDCARD /bin/bash -c "echo HandlePowerKey=ignore >> /etc/systemd/login.d"
	fi

	if [[ $BOARD == station* ]]; then

		cp -R $SRC/packages/blobs/rtl8723bt_fw/* $SDCARD/lib/firmware/rtl_bt/
		cp -R $SRC/packages/blobs/station/firmware/* $SDCARD/lib/firmware/
		if [[ $BRANCH == legacy && ($BOARD == station-m1) ]]; then
			install -m 755 $SRC/packages/bsp/rk3328/m1/rtk_hciattach $SDCARD/usr/bin/rtk_hciattach
			sed -e 's/exit 0//g' -i $SDCARD/etc/rc.local
			echo "su -c '/usr/bin/rtk_hciattach -n -s 115200 /dev/ttyS2 rtk_h5 &'" >> $SDCARD/etc/rc.local
			echo "exit 0" >> $SDCARD/etc/rc.local
		fi

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

	if [[ $BOARD == clockworkpi-a06 ]]; then
		# rotate screen & disable dpms
		mkdir -p "$destination"/etc/X11/xorg.conf.d
		cat <<- EOF > "$destination"/etc/X11/xorg.conf.d/10-monitor.conf
			# set monitor
			Section "Monitor"
			        Identifier "DSI-1"
			        Option "Rotate" "right"
			        Option "DPMS" "false"
			EndSection

			Section "ServerLayout"
			        Identifier "ServerLayout0"
			        Option "BlankTime"  "0"
			        Option "StandbyTime" "0"
			        Option "SuspendTime" "0"
			        Option "OffTime" "0"
			EndSection
		EOF
		# fan support
		install -Dm644 $SRC/packages/bsp/clockworkpi-a06/temp_fan_daemon_a06.py $destination/usr/share/clockworkpi-a06-fan-daemon/bin/temp_fan_daemon_a06.py
		cp $SRC/packages/bsp/clockworkpi-a06/clockworkpi-a06-fan-daemon.service $destination/lib/systemd/system/

		# alsa-ucm-conf profile for DevTerm A06
		mkdir -p $destination/usr/share/alsa/ucm2/Rockchip/es8388
		install -Dm644 $SRC/packages/bsp/clockworkpi-a06/es8388.conf $destination/usr/share/alsa/ucm2/Rockchip/es8388/es8388.conf
		install -Dm644 $SRC/packages/bsp/clockworkpi-a06/HiFi.conf $destination/usr/share/alsa/ucm2/Rockchip/es8388/HiFi.conf
		mkdir -p $destination/usr/share/alsa/ucm2/conf.d/simple-card
		ln -sfv /usr/share/alsa/ucm2/Rockchip/es8388/es8388.conf \
			$destination/usr/share/alsa/ucm2/conf.d/simple-card/rockchip,es8388-codec.conf
	fi

	if [[ $BOARD == z28pro ]]; then

		mkdir -p $destination/usr/local/bin

		# Bluetooth for Z28 PRO
		install -m 755 $SRC/packages/bsp/rk3328/z28pro/8822b_hciattach $destination/usr/bin
		install -m 755 $SRC/packages/bsp/rk3328/z28pro/start_bt.sh $destination/usr/local/bin
		cp $SRC/packages/bsp/rk3328/z28pro/z28pro-bluetooth.service $destination/lib/systemd/system/

	elif [[ $BRANCH == legacy && ($BOARD == rockpi-4[bc] || $BOARD == nanop*4* || $BOARD == orangepi* || $BOARD == firefly*) ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

		if [[ $BOARD == nanop*4* || $BOARD == firefly* || $BOARD == orangepi-rk3399 ]]; then
			sed -i s%BCM4345C5%BCM4356A2%g $destination/lib/systemd/system/rk3399-bluetooth.service
		fi
	fi

	if [[ $BOARD == orangepi4-lts ]]; then
		
		# Bluetooth on orangepi 4 LTS board is handled by a Spreadtrum (sprd) chip and requires
		# a custom hciattach_opi binary, plus a systemd service to run it at boot time
		install -m 755 $SRC/packages/bsp/rk3399/hciattach_opi $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/sprd-bluetooth.service $destination/lib/systemd/system/

	fi

	if [[ $BOARD == nanopim4* ]]; then

		# Fan support
		cp $SRC/packages/bsp/nanopim4/nanopim4-pwm-fan.service $destination/lib/systemd/system/
		install -m 755 $SRC/packages/bsp/nanopim4/nanopim4-pwm-fan.sh $destination/usr/bin/nanopim4-pwm-fan.sh

	fi

	if [[ $BOARD == helios64 ]]; then

		mkdir -p $destination/etc/udev/rules.d/
		mkdir -p $destination/etc/systemd/system/fancontrol.service.d/
		mkdir -p $destination/lib/systemd/system/
		mkdir -p $destination/lib/systemd/system-shutdown/
		cp $SRC/packages/bsp/helios64/50-usb-realtek-net.rules $destination/etc/udev/rules.d/
		cp $SRC/packages/bsp/helios64/70-keep-usb-lan-as-eth1.rules $destination/etc/udev/rules.d/
		cp $SRC/packages/bsp/helios64/90-helios64-ups.rules $destination/etc/udev/rules.d/
		cp $SRC/packages/bsp/helios64/asound.conf $destination/etc/
		install -m 755 $SRC/packages/bsp/helios64/disable_auto_poweron $destination/lib/systemd/system-shutdown/

		### Fancontrol tweaks
		# copy hwmon rules to fix device mapping
		# changed to only use one file regardless of branch
		install -m 644 $SRC/packages/bsp/helios64/90-helios64-hwmon.rules $destination/etc/udev/rules.d/

		install -m 644 $SRC/packages/bsp/helios64/fancontrol.service.pid-override $destination/etc/systemd/system/fancontrol.service.d/pid.conf

		# copy fancontrol config
		install -m 644 $SRC/packages/bsp/helios64/fancontrol.conf $destination/etc/fancontrol

		# LED tweak
		if [[ $BRANCH == legacy ]]; then
			install -m 644 $SRC/packages/bsp/helios64/helios64-heartbeat-led-legacy.service $destination/etc/systemd/system/helios64-heartbeat-led.service
		else
			install -m 644 $SRC/packages/bsp/helios64/helios64-heartbeat-led.service $destination/etc/systemd/system/
		fi

		# UPS service
		cp $SRC/packages/bsp/helios64/helios64-ups.service $destination/lib/systemd/system/
		cp $SRC/packages/bsp/helios64/helios64-ups.timer $destination/lib/systemd/system/
		install -m 755 $SRC/packages/bsp/helios64/helios64-ups.sh $destination/usr/bin/helios64-ups.sh

	fi

	if [[ $BOARD == rk3318-box ]]; then

                # Optional board dtbo selection script
                mkdir -p $destination/usr/local/bin
                install -m 755 $SRC/packages/bsp/rk3318/rk3318-config $destination/usr/sbin

        fi

	if [[ $BOARD == pinebook-pro ]]; then

		# special keys
		mkdir -p "${destination}"/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/
		cp $SRC/packages/bsp/pinebook-pro/pointers.xml "${destination}"/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/

		# touchpad and keyboard tweaks
		mkdir -p "${destination}"/etc/X11/xorg.conf.d/
		# from https://github.com/ayufan-rock64/linux-package/tree/master/root-pinebookpro
		cp "${SRC}"/packages/bsp/pinebook-pro/40-pinebookpro-touchpad.conf "${destination}"/etc/X11/xorg.conf.d/

		# keyboard hwdb
		mkdir -p "${destination}"/etc/udev/hwdb.d/
		cp "${SRC}"/packages/bsp/pinebook-pro/10-usb-kbd.hwdb "${destination}"/etc/udev/hwdb.d/
	fi

	# Graphics and media
	mkdir -p $destination/etc/udev/rules.d
	cp $SRC/packages/bsp/rk3399/50-mali.rules $destination/etc/udev/rules.d/
	cp $SRC/packages/bsp/rk3399/50-rk3399-vpu.rules $destination/etc/udev/rules.d/
	mkdir -p $destination/etc/sysfs.d
	cp $SRC/packages/bsp/rk3399/20-gpu-governor.conf $destination/etc/sysfs.d/

}
