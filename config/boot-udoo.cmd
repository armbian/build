setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4 rootwait console=ttymxc1,115200 video=mxcfb0:dev=hdmi,1920x1080M@60,if=RGB24,bpp=32 rd.dm=0 rd.luks=0 rd.lvm=0 raid=noautodetect pci=nomsi ahci_imx.hotplug=1 quiet
ext2load mmc 0 0x49000000 /boot/imx6q-udoo.dtb
ext2load mmc 0 0x46000000 /boot/vmlinuz-3.19.0-rc5-udoo
env set fdt_high ffffffff
bootz 0x46000000 - 0x49000000
