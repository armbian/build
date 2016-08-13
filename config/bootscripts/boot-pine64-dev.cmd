setenv bootargs "console=ttyS0,115200 root=/dev/mmcblk0p1 rootwait rootfstype=ext4 panic=10 consoleblank=0 enforcing=0 loglevel=1"

ext4load mmc 0 ${fdt_addr_r} /boot/dtb/allwinner/${fdtfile} || fatload mmc 0 ${fdt_addr_r} /dtb/allwinner/${fdtfile} || ext4load mmc 0 ${fdt_addr_r} /dtb/allwinner/${fdtfile}
ext4load mmc 0 ${ramdisk_addr_r} /boot/uInitrd || fatload mmc 0 ${ramdisk_addr_r} uInitrd || ext4load mmc 0 ${ramdisk_addr_r} uInitrd || setenv ramdisk_addr_r "-"
ext4load mmc 0 ${kernel_addr_r} /boot/Image || fatload mmc 0 ${kernel_addr_r} Image || ext4load mmc 0 ${kernel_addr_r} Image
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}

# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
