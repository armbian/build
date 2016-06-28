if ext4load mmc 0 0x00000000 /boot/.verbose
then
setenv verbosity 7
else
setenv verbosity 1
fi
setenv bootargs "root=/dev/mmcblk0p1 rootfstype=ext4 rootwait console=tty1 video=mxcfb0:dev=hdmi,1920x1080M@60,if=RGB24,bpp=32 rd.dm=0 rd.luks=0 rd.lvm=0 raid=noautodetect pci=nomsi ahci_imx.hotplug=1 quiet loglevel=1 loglevel=${verbosity} consoleblank=0"
if ext4load mmc 0 0x00000000 /boot/.next
then
  setenv fdt_file imx6q-udoo.dtb
else
  setenv fdt_file imx6q-udoo-hdmi.dtb
fi
ext2load mmc 0 ${fdt_addr} /boot/dtb/${fdt_file} || fatload mmc 0 ${fdt_addr} dtb/${fdt_file}
ext2load mmc 0 ${loadaddr} /boot/${image} || fatload mmc 0 ${loadaddr} ${image}
bootz ${loadaddr} - ${fdt_addr}
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 

