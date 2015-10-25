setenv fdt_file imx6sx-udoo-neo-hdmi-m4.dtb
setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4 rootwait console=ttymxc0,115200 rd.dm=0 rd.luks=0 rd.lvm=0 rw uart_from_osc loglevel=1
ext2load mmc ${mmcdev}:${mmcpart} 0x84000000 /boot/bin/m4startup.fw
ext2load mmc ${mmcdev}:${mmcpart} ${loadaddr} /boot${image}
ext2load mmc ${mmcdev}:${mmcpart} ${fdt_addr} /boot/dtb/${fdt_file}
bootaux 0x84000000
bootz ${loadaddr} - ${fdt_addr}
# Recompile: mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 
# (c) www.armbian.com