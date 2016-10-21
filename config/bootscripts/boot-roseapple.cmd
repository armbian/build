
setenv rootdev "/dev/mmcblk0p1"

setenv fdt_high "0xffffffff"
setenv bootargs "earlyprintk clk_ignore_unused selinux=0 scandelay root=${rootdev} rw console=tty1 rootfstype=ext4 loglevel=1 rootwait ${extraargs}"
ext4load mmc 0:1 ${fdt_addr_r} /boot/dtb/actduino_bubble_gum_sdboot_linux.dtb || fatload mmc 0:1 ${fdt_addr_r} dtb/actduino_bubble_gum_sdboot_linux.dtb || ext4load mmc 0:1 ${fdt_addr_r} dtb/actduino_bubble_gum_sdboot_linux.dtb
ext4load mmc 0:1 ${ramdisk_addr_r} /boot/uInitrd || fatload mmc 0:1 ${ramdisk_addr_r} uInitrd || ext4load mmc 0:1 ${ramdisk_addr_r} uInitrd
ext4load mmc 0:1 ${kernel_addr_r} /boot/zImage || fatload mmc 0:1 ${kernel_addr_r} zImage || ext4load mmc 0:1 ${kernel_addr_r} zImage
bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
