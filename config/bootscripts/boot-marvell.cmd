
setenv rootdev "/dev/mmcblk0p1"

if ext4load mmc 0:1 0x00000000 /boot/.verbose
then
setenv verbosity 7
else
setenv verbosity 1
fi

# configure addresses
setenv kerneladdr 0x2000000
setenv fdtaddr 0x5F00000
setenv ramdiskaddr 0x6000000
setenv fdt_high 0x07a12000

setenv ethaddr  00:50:43:84:fb:2f
setenv eth1addr 00:50:43:25:fb:84
setenv eth2addr 00:50:43:84:25:2f
setenv eth3addr 00:50:43:0d:19:18
#
setenv bootargs "selinux=0 cgroup_disable=memory scandelay root=${rootdev} rw rootfstype=ext4 console=ttyS0,115200 loglevel=${verbosity} rootwait ${extraargs}"
ext2load mmc 0:1 ${fdtaddr} boot/dtb/armada-388-clearfog.dtb
ext2load mmc 0:1 ${ramdiskaddr} boot/uInitrd
ext2load mmc 0:1 ${loadaddr} boot/zImage
bootz ${loadaddr} - ${fdtaddr}
#ramdisk currently broken
#bootz ${loadaddr} ${ramdiskaddr} ${fdtaddr} 
# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 