setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4 rootwait console=tty1 video=mxcfb0:dev=hdmi,1920x1080M@60,if=RGB24,bpp=32 rd.dm=0 rd.luks=0 rd.lvm=0 raid=noautodetect pci=nomsi ahci_imx.hotplug=1 consoleblank=0 vt.global_cursor_default=0 quiet
ext2load mmc 0 0x18000000 /boot/dtb/${fdt_file}
ext2load mmc 0 0x12000000 /boot/zImage
bootz 0x12000000 - 0x18000000
