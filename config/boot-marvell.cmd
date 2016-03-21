if ext4load mmc 0:1 0x00000000 /boot/.verbose
then
setenv verbosity 7
else
setenv verbosity 1
fi

setenv ethaddr  00:50:43:84:fb:2f
setenv eth1addr 00:50:43:25:fb:84
setenv eth2addr 00:50:43:84:25:2f
setenv eth3addr 00:50:43:0d:19:18
#
setenv bootargs "selinux=0 cgroup_disable=memory scandelay root=/dev/mmcblk0p1 rw rootfstype=ext4 console=ttyS0,115200 loglevel=${verbosity} rootwait"
ext2load mmc 0:1 ${fdtaddr} boot/dtb/armada-388-clearfog.dtb
ext2load mmc 0:1 ${loadaddr} boot/zImage
bootz ${loadaddr} - ${fdtaddr}
# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 