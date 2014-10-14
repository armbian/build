setenv bootargs console=ttyS0,115200 sunxi_g2d_mem_reserve=0 sunxi_ve_mem_reserve=0  sunxi_no_mali_mem_reserve root=/dev/mmcblk0p1 rootwait panic=10 ${extra}
ext4load mmc 0 0x46000000 /boot/uImage
ext4load mmc 0 0x49000000 /boot/sun7i-a20-bananapi.dtb
env set fdt_high ffffffff
bootm 0x46000000 - 0x49000000
