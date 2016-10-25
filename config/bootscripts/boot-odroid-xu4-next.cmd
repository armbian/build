# a boot script for U-Boot / Odroid XU4
#
# It requires a list of environment variables to be defined before load (in includes files uboot/.../exy*.h):
# platform dependent: boardname, fdtfile, console
# system dependent: mmcbootdev, mmcbootpart, mmcrootdev, mmcrootpart, rootfstype
#

setenv rootdev "/dev/mmcblk1p1"
setenv load_addr 	0x44000000

setenv consolecfg       "console=tty1 console=ttySAC2,115200n8"

if load mmc ${mmcbootdev}:${mmcbootpart} ${load_addr} /boot/armbianEnv.txt || load mmc ${mmcbootdev}:${mmcbootpart} ${load_addr} armbianEnv.txt; then
        env import -t ${load_addr} ${filesize}
fi

setenv bootargs "${consolecfg} root=${rootdev} rootfstype=${rootfstype} rootwait rw earlyprintk ${opts}";
load mmc ${mmcbootdev}:${mmcbootpart} ${kerneladdr} /boot/zImage;
load mmc ${mmcbootdev}:${mmcbootpart} ${initrdaddr} /boot/uInitrd;
load mmc ${mmcbootdev}:${mmcbootpart} ${ftdaddr} /boot/dtb/exynos5422-odroidxu4.dtb;

bootz ${kerneladdr} ${initrdaddr} ${ftdaddr};

# Generate boot.scr:
# mkimage -c none -A arm -T script -d boot.cmd boot.scr