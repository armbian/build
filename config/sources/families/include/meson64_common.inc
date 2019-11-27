UBOOT_TARGET_MAP="u-boot-dtb.img;;u-boot.bin.sd.bin:u-boot.bin u-boot-dtb.img"
BOOTSCRIPT="boot-meson64.cmd:boot.cmd"
BOOTENV_FILE='meson64-next.txt'
LINUXFAMILY=meson64
ARCH=arm64
SERIALCON=ttyAML0
SRC_LOADADDR='LOADADDR=0x1080000'
OVERLAY_PREFIX='meson'

# this family does not need it
ATF_COMPILE="no"

if [[ $BOARD == lafrite ]]; then
		UBOOT_TARGET_MAP="u-boot-dtb.img;;u-boot.bin:u-boot.bin u-boot-dtb.img"
fi

CPUMIN=500000
CPUMAX=1536000
GOVERNOR=conservative

case $BRANCH in
        dev)

		KERNELBRANCH='branch:linux-5.4.y'
		KERNELPATCHDIR='meson64-'$BRANCH

        ;;
esac


# this helper function includes postprocess for p212 and its variants.
# $1 PATH for uboot blob repo
# $2 dir name in uboot blob repo
uboot_gxl_postprocess()
{
	mv u-boot.bin bl33.bin

	$1/blx_fix.sh 	$1/$2/bl30.bin \
			$1/$2/zero_tmp \
			$1/$2/bl30_zero.bin \
			$1/$2/bl301.bin \
			$1/$2/bl301_zero.bin \
			$1/$2/bl30_new.bin bl30

	python $1/acs_tool.pyc $1/$2/bl2.bin \
			$1/$2/bl2_acs.bin \
			$1/$2/acs.bin 0

	$1/blx_fix.sh 	$1/$2/bl2_acs.bin \
			$1/$2/zero_tmp \
			$1/$2/bl2_zero.bin \
			$1/$2/bl21.bin \
			$1/$2/bl21_zero.bin \
			$1/$2/bl2_new.bin bl2

	$1/$2/aml_encrypt_gxl 	--bl3enc --input $1/$2/bl30_new.bin
	$1/$2/aml_encrypt_gxl 	--bl3enc --input $1/$2/bl31.img
	$1/$2/aml_encrypt_gxl 	--bl3enc --input bl33.bin

	$1/$2/aml_encrypt_gxl 	--bl2sig --input $1/$2/bl2_new.bin \
				--output bl2.n.bin.sig

	$1/$2/aml_encrypt_gxl 	--bootmk \
				--output u-boot.bin \
				--bl2 bl2.n.bin.sig \
				--bl30 $1/$2/bl30_new.bin.enc \
				--bl31 $1/$2/bl31.img.enc \
				--bl33 bl33.bin.enc
}

write_uboot_platform()
{
	dd if=$1/u-boot.bin of=$2 bs=1 count=442 conv=fsync > /dev/null 2>&1
	dd if=$1/u-boot.bin of=$2 bs=512 skip=1 seek=1 conv=fsync > /dev/null 2>&1
}

family_tweaks_bsp()
{
	mkdir -p $destination/etc/udev/rules.d
	mkdir -p $destination/usr/local/bin
	cp $SRC/packages/bsp/rockchip/hdmi.rules $destination/etc/udev/rules.d
	install -m 755 $SRC/packages/bsp/rockchip/hdmi-hotplug $destination/usr/local/bin

	mkdir -p "$destination"/etc/X11/xorg.conf.d
	cat <<-EOF > "$destination"/etc/X11/xorg.conf.d/02-driver.conf
	# set fbdev as default driver.
	Section "Device"
         Identifier "NOGPU"
         Driver "fbdev"
	EndSection
	EOF
}
