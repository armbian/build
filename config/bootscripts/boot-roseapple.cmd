setenv fdt_high "0xffffffff" 
setenv bootargs "earlyprintk clk_ignore_unused selinux=0 scandelay root=/dev/mmcblk0p2 rw console=tty1 rootfstype=ext4 loglevel=1 rootwait" 
fatload mmc 0:1 0x04000000 dtb/actduino_bubble_gum_sdboot_linux.dtb 
fatload mmc 0:1 0x00008000 zImage
bootz 0x00008000 - 0x04000000
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 
