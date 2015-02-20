setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4 rootwait console=tty1 video=mxcfb0:dev=hdmi,1920x1080M@60,if=RGB24,bpp=32 ahci_imx.hotplug=1 quiet
ext2load mmc 0 0x18000000 /boot/dtb/${fdt_file}
ext2load mmc 0 0x12000000 /boot/zImage
bootz 0x12000000 - 0x18000000
