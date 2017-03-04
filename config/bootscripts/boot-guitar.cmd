
setenv rootdev "/dev/mmcblk0p1"

# console=ttyS3 # serial

setenv bootargs "earlyprintk clk_ignore_unused scandelay root=${rootdev} rw console=tty1 rootfstype=ext4 loglevel=1 rootwait ${extraargs}"
setenv os_type linux
ext4load mmc 0:1 ${fdt_addr_r} /boot/dtb/lemaker_guitar_bbb.dtb || fatload mmc 0:1 ${fdt_addr_r} dtb/lemaker_guitar_bbb.dtb || ext4load mmc 0:1 ${fdt_addr_r} dtb/lemaker_guitar_bbb.dtb
ext4load mmc 0:1 ${ramdisk_addr_r} /boot/uInitrd || fatload mmc 0:1 ${ramdisk_addr_r} uInitrd || ext4load mmc 0:1 ${ramdisk_addr_r} uInitrd
ext4load mmc 0:1 ${kernel_addr_r} /boot/zImage || fatload mmc 0:1 ${kernel_addr_r} zImage || ext4load mmc 0:1 ${kernel_addr_r} zImage
bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
