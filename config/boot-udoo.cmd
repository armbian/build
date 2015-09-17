setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4 rootwait console=ttymxc1,115200 video=mxcfb0:dev=hdmi,1920x1080M@60,if=RGB24,bpp=32 rd.dm=0 rd.luks=0 rd.lvm=0 raid=noautodetect pci=nomsi ahci_imx.hotplug=1 quiet
ext2load mmc 0 ${fdt_addr} /boot/dtb/imx6q-udoo.dtb
ext2load mmc 0 ${loadaddr} /boot/zImage
bootz ${loadaddr} - ${fdt_addr}


