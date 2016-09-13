setenv fdt_high "0xffffffff" 
setenv bootargs "earlyprintk clk_ignore_unused selinux=0 scandelay root=/dev/mmcblk0p2 rw console=tty1 rootfstype=ext4 loglevel=1 rootwait" 
fatload mmc 0:1 ${fdt_addr_r} dtb/actduino_bubble_gum_sdboot_linux.dtb 
fatload mmc 0:1 ${ramdisk_addr_r} uInitrd
fatload mmc 0:1 ${kernel_addr_r} zImage
bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 
