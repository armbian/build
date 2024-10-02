# do the virtio dance
${devtype} scan
${devtype} info
ls ${devtype} ${devnum}:${distro_bootpart} /boot

# higher load address; the default causes the initrd to be overwritten when the bzImage is unpacked....
setenv ramdisk_addr_r 0x8000000
echo KERNEL LOAD ADDRESS: kernel_addr_r: ${kernel_addr_r}
echo INITRD LOAD ADDRESS: ramdisk_addr_r: ${ramdisk_addr_r}

# /vmlinuz and /initrd.img are standard Debian symlinks to the "latest installed kernel"
load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /vmlinuz
# Attention, this is the raw initrd.img, NOT uInitrd for uboot/ARM
load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} /initrd.img

# boot params
# @TODO: armbianEnv.txt, etc.
setenv bootargs root=LABEL=armbi_root ro  console=ttyS0

# zboot knows how to handle bzImage...
zboot ${kernel_addr_r} - ${ramdisk_addr_r} ${filesize}
