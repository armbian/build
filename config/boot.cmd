setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p1 rootwait panic=10
ext4load mmc 0 0x46000000 /boot/uImage
ext4load mmc 0 0x49000000 /boot/dtb/WHICH
env set fdt_high ffffffff
bootm 0x46000000 - 0x49000000
