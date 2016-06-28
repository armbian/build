# imx6sx-udoo-neo-basic.dtb
# imx6sx-udoo-neo-basic-hdmi.dtb
# imx6sx-udoo-neo-basic-hdmi-m4.dtb
# imx6sx-udoo-neo-basicks.dtb
# imx6sx-udoo-neo-basicks-hdmi.dtb
# imx6sx-udoo-neo-basicks-hdmi-m4.dtb
# imx6sx-udoo-neo-basicks-lvds15.dtb
# imx6sx-udoo-neo-basicks-lvds15-m4.dtb
# imx6sx-udoo-neo-basicks-lvds7.dtb
# imx6sx-udoo-neo-basicks-lvds7-m4.dtb
# imx6sx-udoo-neo-basicks-m4.dtb
# imx6sx-udoo-neo-basic-lvds15.dtb
# imx6sx-udoo-neo-basic-lvds15-m4.dtb
# imx6sx-udoo-neo-basic-lvds7.dtb
# imx6sx-udoo-neo-basic-lvds7-m4.dtb
# imx6sx-udoo-neo-basic-m4.dtb
# imx6sx-udoo-neo-extended.dtb
# imx6sx-udoo-neo-extended-hdmi.dtb
# imx6sx-udoo-neo-extended-hdmi-m4.dtb
# imx6sx-udoo-neo-extended-lvds15.dtb
# imx6sx-udoo-neo-extended-lvds15-m4.dtb
# imx6sx-udoo-neo-extended-lvds7.dtb
# imx6sx-udoo-neo-extended-lvds7-m4.dtb
# imx6sx-udoo-neo-extended-m4.dtb
# imx6sx-udoo-neo-full.dtb
# imx6sx-udoo-neo-full-hdmi.dtb
# imx6sx-udoo-neo-full-hdmi-m4.dtb
# imx6sx-udoo-neo-full-lvds15.dtb
# imx6sx-udoo-neo-full-lvds15-m4.dtb
# imx6sx-udoo-neo-full-lvds7.dtb
# imx6sx-udoo-neo-full-lvds7-m4.dtb
# imx6sx-udoo-neo-full-m4.dtb
#
# Pick one of above:
#

if test "${board}" = "Neo"; then echo "Booting Neo"; fi

setenv fdt_file imx6sx-udoo-neo-full-m4.dtb

setenv bootargs root=/dev/mmcblk0p1 rootfstype=ext4 rootwait console=ttymxc0,115200 rd.dm=0 rd.luks=0 rd.lvm=0 rw uart_from_osc loglevel=1
ext2load mmc ${mmcdev}:${mmcpart} 0x84000000 /boot/bin/m4startup.fw
ext2load mmc ${mmcdev}:${mmcpart} ${loadaddr} /boot/${image}
ext2load mmc ${mmcdev}:${mmcpart} ${fdt_addr} /boot/dtb/${fdt_file}
bootz ${loadaddr} - ${fdt_addr}
# Recompile: mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 
# (c) www.armbian.com