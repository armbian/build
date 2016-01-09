setenv bootargs "selinux=0 scandelay root=/dev/mmcblk0p1 rw rootfstype=ext4 console=ttyS0,115200 loglevel=1 rootwait"
ext2load mmc 0:1 ${fdtaddr} boot/dtb/armada-388-clearfog.dtb
ext2load mmc 0:1 ${loadaddr} boot/zImage
bootz ${loadaddr} - ${fdtaddr}