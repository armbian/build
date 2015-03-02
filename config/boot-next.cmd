setenv bootargs console=tty1 root=/dev/mmcblk0p1 rootwait panic=10 consoleblank=0 
ext4load mmc 0 0x49000000 /boot/dtb/${fdtfile}
ext4load mmc 0 0x46000000 /boot/zImage
env set fdt_high ffffffff
bootz 0x46000000 - 0x49000000
