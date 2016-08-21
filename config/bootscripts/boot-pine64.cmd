
if ext4load mmc 0 0x00000000 /boot/.next || fatload mmc 0 0x00000000 .next || ext4load mmc 0 0x00000000 .next; then
	setenv bootargs "console=ttyS0,115200 root=/dev/mmcblk0p1 rootwait rootfstype=ext4 panic=10 consoleblank=0 enforcing=0 loglevel=1"
	ext4load mmc 0 ${fdt_addr_r} /boot/dtb/allwinner/${fdtfile} || fatload mmc 0 ${fdt_addr_r} /dtb/allwinner/${fdtfile} || ext4load mmc 0 ${fdt_addr_r} /dtb/allwinner/${fdtfile}
	ext4load mmc 0 ${ramdisk_addr_r} /boot/uInitrd || fatload mmc 0 ${ramdisk_addr_r} uInitrd || ext4load mmc 0 ${ramdisk_addr_r} uInitrd || setenv ramdisk_addr_r "-"
	ext4load mmc 0 ${kernel_addr_r} /boot/Image || fatload mmc 0 ${kernel_addr_r} Image || ext4load mmc 0 ${kernel_addr_r} Image
	booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
else
	setenv bootargs "console=ttyS0,115200n8 no_console_suspend earlycon=uart,mmio32,0x01c28000 mac_addr=${ethaddr} root=/dev/mmcblk0p1 rootwait panic=10 consoleblank=0 enforcing=0 loglevel=2"
	ext4load mmc 0 ${fdt_addr} /boot/${pine64_model}.dtb || fatload mmc 0 ${fdt_addr} ${pine64_model}.dtb || ext4load mmc 0 ${fdt_addr} ${pine64_model}.dtb
	ext4load mmc 0 ${initrd_addr} /boot/uInitrd || fatload mmc 0 ${initrd_addr} uInitrd || ext4load mmc 0 ${initrd_addr} uInitrd || setenv initrd_addr "-"
	ext4load mmc 0 ${kernel_addr} /boot/Image || fatload mmc 0 ${kernel_addr} Image || ext4load mmc 0 ${kernel_addr} Image
	booti ${kernel_addr} ${initrd_addr} ${fdt_addr}
fi

# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
