# a boot script for U-Boot / Odroid XU4
#
# It requires a list of environment variables to be defined before load (in includes files uboot/.../exy*.h):
# platform dependent: boardname, fdtfile, console
# system dependent: mmcbootdev, mmcbootpart, mmcrootdev, mmcrootpart, rootfstype
#

setenv kerneladdr       0x40800000
setenv initrdaddr       0x42000000
setenv ftdaddr          0x44000000

setenv consolecfg       "console=tty1 console=ttySAC2,115200n8"

setenv rootfs           "/dev/mmcblk1p1"

setenv bootargs "${consolecfg} root=${rootfs} rootfstype=${rootfstype} rootwait rw earlyprintk ${opts}";
load mmc ${mmcbootdev}:${mmcbootpart} ${kerneladdr} /boot/zImage;
load mmc ${mmcbootdev}:${mmcbootpart} ${initrdaddr} /boot/uInitrd;
load mmc ${mmcbootdev}:${mmcbootpart} ${ftdaddr} /boot/dtb/exynos5422-odroidxu4.dtb;

bootz ${kerneladdr} ${initrdaddr} ${ftdaddr};

# Generate boot.scr:
# mkimage -c none -A arm -T script -d boot.cmd boot.scr