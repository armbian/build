#!/bin/bash
set -ex
new_rootfs_image_uuid=$(sed -e 's/^.*root=UUID=//' -e 's/ .*$//' < /proc/cmdline)
gzip -c /boot/vmlinuz-*-sm8250 > /tmp/Image.gz

cat /tmp/Image.gz /usr/lib/linux-image-*-sm8250/qcom/sm8250-oneplus-kebab.dtb > /tmp/Image.gz-dtb

source /boot/armbianEnv.txt
/usr/bin/mkbootimg \
        --kernel /tmp/Image.gz-dtb \
        --ramdisk /boot/initrd.img-*-sm8250 \
        --base 0x0 \
        --second_offset 0x00f00000 \
        --cmdline "root=UUID=${new_rootfs_image_uuid} slot_suffix=${abl_boot_partition_label#boot}" \
        --kernel_offset 0x8000 \
        --ramdisk_offset 0x1000000 \
        --tags_offset 0x100 \
        --pagesize 4096 \
        -o /boot/armbian-kernel.img
rm -f /tmp/Image.gz /tmp/Image.gz-dtb

if [ -n "$abl_boot_partition_label" ];then
	echo abl boot partition label is $abl_boot_partition_label
	dd if=/boot/armbian-kernel.img of=/dev/disk/by-partlabel/${abl_boot_partition_label}
else
	echo abl boot partition label is not defined, exit
	exit
fi
