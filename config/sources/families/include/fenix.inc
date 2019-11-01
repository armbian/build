# source define for khadas product family

# common
BOOTSOURCE=$MAINLINE_UBOOT_SOURCE
BOOTDIR=$MAINLINE_UBOOT_DIR
BOOTBRANCH='branch:master'
UBOOT_USE_GCC='> 8.0'
ARCH=arm64
KERNEL_IMAGE_TYPE=Image
BOOTSCRIPT="boot-fenix.cmd:boot.cmd"
BOOTENV_FILE='fenix.txt'
BOOTPATCHDIR=fenix
KERNELPATCHDIR=fenix
ATF_COMPILE="no"

KERNELSOURCE=$MAINLINE_KERNEL_SOURCE
KERNELBRANCH='branch:linux-5.3.y'
KERNELDIR=$MAINLINE_KERNEL_DIR
KERNEL_USE_GCC='> 8.0'

family_tweaks_bsp()
{
	mkdir -p "$destination"/etc/X11/xorg.conf.d
	cat <<-EOF > "$destination"/etc/X11/xorg.conf.d/02-driver.conf
	# set fbdev as default driver.
	Section "Device"
         Identifier "NOGPU"
         Driver "fbdev"
	EndSection
	EOF
}
