BOOTDIR='u-boot-odroidc1'
BOOTSOURCE='https://github.com/hardkernel/u-boot.git'
BOOTBRANCH='branch:odroidc-v2011.03'
UBOOT_COMPILER="arm-linux-gnueabihf-"
UBOOT_USE_GCC='< 4.9'
UBOOT_TARGET_MAP=';;sd_fuse/bl1.bin.hardkernel sd_fuse/u-boot.bin'

ARCH=armhf
LINUXFAMILY=meson
KERNEL_IMAGE_TYPE=uImage
SRC_LOADADDR='LOADADDR=0x00208000'

SERIALCON="ttyAML0"

CPUMIN=504000
CPUMAX=1632000
GOVERNOR=ondemand

case $BRANCH in
	legacy)

		KERNELBRANCH="branch:linux-5.11.y"
		KERNELPATCHDIR='meson-'$BRANCH

		BUILD_DESKTOP=no

        ;;
	current)

		KERNELBRANCH="branch:linux-5.14.y"
		KERNELPATCHDIR='meson-'$BRANCH

		BUILD_DESKTOP=no

	;;
	edge)

		KERNELDIR='linux-meson'
		KERNELSOURCE='https://github.com/xdarklight/linux'
		KERNELBRANCH="branch:meson-mx-integration-5.18-20220417"
		KERNELPATCHDIR='meson-'$BRANCH

	;;
esac

write_uboot_platform()
{
	dd if=$1/bl1.bin.hardkernel of=$2 bs=1 count=442 conv=fsync > /dev/null 2>&1
	dd if=$1/bl1.bin.hardkernel of=$2 bs=512 skip=1 seek=1 conv=fsync > /dev/null 2>&1
	dd if=$1/u-boot.bin of=$2 bs=512 seek=64 conv=fsync > /dev/null 2>&1
	dd if=/dev/zero of=$2 seek=1024 count=32 bs=512 conv=fsync > /dev/null 2>&1
}

family_tweaks()
{
	:
}

family_tweaks_bsp()
{
	mkdir -p "$destination/etc/X11/xorg.conf.d"
	cat <<-EOF >"$destination/etc/X11/xorg.conf.d/02-driver.conf"
	Section "OutputClass"
		Identifier "Amlogic"
		MatchDriver "meson"
		Driver "modesetting"
		Option "PrimaryGPU" "true"
	EndSection
	EOF
}
