run autodetectfdt
setenv bootargs "root=/dev/mmcblk0p1 rootfstype=ext4 rootwait console=ttymxc0,115200 console=tty1 video=mxcfb0:dev=hdmi,1920x1080M@60,if=RGB24,bpp=32 rd.dm=0 rd.luks=0 rd.lvm=0 raid=noautodetect pci=nomsi ahci_imx.hotplug=1 consoleblank=0 vt.global_cursor_default=0 quiet loglevel=3"
ext2load mmc 0 ${fdt_addr} /boot/dtb/${fdt_file} || fatload mmc 0 ${fdt_addr} /dtb/${fdt_file} || ext4load mmc 0 ${fdt_addr} /dtb/${fdt_file}
ext2load mmc 0 ${loadaddr} /boot/zImage || fatload mmc 0 ${loadaddr} zImage || ext4load mmc 0 ${loadaddr} zImage
bootz ${loadaddr} - ${fdt_addr}
# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 