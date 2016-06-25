if ext4load mmc 0 0x00000000 /boot/.verbose
then
setenv verbosity 7
else
setenv verbosity 1
fi
setenv bootargs "console=ttyS0,115200 console=tty1 root=/dev/mmcblk0p1 rootwait rootfstype=ext4 cgroup_enable=memory swapaccount=1 sunxi_ve_mem_reserve=0 sunxi_g2d_mem_reserve=0 sunxi_no_mali_mem_reserve sunxi_fb_mem_reserve=16 hdmi.audio=EDID:0 disp.screen0_output_mode=1920x1080p60 panic=10 consoleblank=0 enforcing=0 loglevel=${verbosity}"
#--------------------------------------------------------------------------------------------------------------------------------
# Boot loader script to boot with different boot methods for old and new kernel
#--------------------------------------------------------------------------------------------------------------------------------
if ext4load mmc 0 0x00000000 /boot/.next || fatload mmc 0 0x00000000 .next || ext4load mmc 0 0x00000000 .next
then
# sunxi mainline kernel
#--------------------------------------------------------------------------------------------------------------------------------
ext4load mmc 0 ${fdt_addr_r} /boot/dtb/${fdtfile} || fatload mmc 0 ${fdt_addr_r} /dtb/${fdtfile} || ext4load mmc 0 ${fdt_addr_r} /dtb/${fdtfile}
ext4load mmc 0 ${ramdisk_addr_r} /boot/uInitrd || fatload mmc 0 ${ramdisk_addr_r} uInitrd || ext4load mmc 0 ${ramdisk_addr_r} uInitrd || setenv ramdisk_addr_r "-"
ext4load mmc 0 ${kernel_addr_r} /boot/zImage || fatload mmc 0 ${kernel_addr_r} zImage || ext4load mmc 0 ${kernel_addr_r} zImage
bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
#--------------------------------------------------------------------------------------------------------------------------------
else
# sunxi android kernel
#--------------------------------------------------------------------------------------------------------------------------------
ext4load mmc 0 ${fdt_addr_r} /boot/script.bin || fatload mmc 0 ${fdt_addr_r} script.bin || ext4load mmc 0 ${fdt_addr_r} script.bin
ext4load mmc 0 ${ramdisk_addr_r} /boot/uInitrd || fatload mmc 0 ${ramdisk_addr_r} uInitrd || ext4load mmc 0 ${ramdisk_addr_r} uInitrd || setenv ramdisk_addr_r "-"
ext4load mmc 0 ${kernel_addr_r} /boot/zImage || fatload mmc 0 ${kernel_addr_r} zImage || ext4load mmc 0 ${kernel_addr_r} zImage
bootz ${kernel_addr_r} ${ramdisk_addr_r}
#--------------------------------------------------------------------------------------------------------------------------------
fi
# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 
