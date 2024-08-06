# Amlogic S805 C1 quad core 1GB RAM SoC GBE
BOARD_NAME="Odroid C1"
BOARDFAMILY="meson8b"
BOARD_MAINTAINER=""
KERNEL_TARGET="current,edge"

BOOTDIR='u-boot-odroidc1'
BOOTSOURCE='https://github.com/hardkernel/u-boot.git'
BOOTBRANCH='branch:odroidc-v2011.03'
BOOTPATCHDIR="legacy"
UBOOT_COMPILER="arm-linux-gnueabi-"
UBOOT_USE_GCC='< 4.9'
BOOTCONFIG="odroidc_config"
BOOTSCRIPT="boot-odroid-c1.ini:boot.ini"

UBOOT_TARGET_MAP=';;sd_fuse/bl1.bin.hardkernel sd_fuse/u-boot.bin'

BOOTSIZE="200"
BOOTFS_TYPE="fat"

write_uboot_platform() {
	dd if=$1/bl1.bin.hardkernel of=$2 bs=1 count=442 conv=fsync > /dev/null 2>&1
	dd if=$1/bl1.bin.hardkernel of=$2 bs=512 skip=1 seek=1 conv=fsync > /dev/null 2>&1
	dd if=$1/u-boot.bin of=$2 bs=512 seek=64 conv=fsync > /dev/null 2>&1
	dd if=/dev/zero of=$2 seek=1024 count=32 bs=512 conv=fsync > /dev/null 2>&1
}
