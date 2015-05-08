setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4 rootwait 
setenv fdt_file /boot/dtb/imx6sx-udooneo.dtb
run loadimage
run mmcboot 