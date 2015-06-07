echo "Booting..."
setenv fdt_file imx6sx-udooneo.dtb
setenv bootargs root=/dev/mmcblk1p1 rootfstype=ext4 rootwait console=ttymxc0,115200
ext2load mmc 0 ${loadaddr} ${prefix}zImage || fatload mmc 0 ${loadaddr} ${prefix}zImage
ext2load mmc 0 ${fdt_addr} ${prefix}dtb/${fdt_file} || fatload mmc 0 ${fdt_addr} ${prefix}dtb/${fdt_file}
bootz ${loadaddr} - ${fdt_addr}
# Recompile: mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 
# (c) www.armbian.com