#!/bin/bash
set -ex
machine_model=$(cat /sys/firmware/devicetree/base/model|tr '\0' '\n')
case $machine_model in
	"Xiaomi Mi 10 (SMS)")
		panel_type=sms
		;;
	"Xiaomi Mi 10 (CSOT)")
		panel_type=csot
		;;
	*)
		echo "$machine_model is not supported, exit"
		exit
		;;
esac
new_rootfs_image_uuid=$(sed -e 's/^.*root=UUID=//' -e 's/ .*$//' < /proc/cmdline)
gzip -c /boot/vmlinuz-*-sm8250 > /tmp/Image.gz

cat /tmp/Image.gz /usr/lib/linux-image-*-sm8250/qcom/sm8250-xiaomi-umi-${panel_type}.dtb > /tmp/Image.gz-dtb-${panel_type}

source /boot/armbianEnv.txt
/usr/bin/mkbootimg \
        --kernel /tmp/Image.gz-dtb-${panel_type} \
        --ramdisk /boot/initrd.img-*-sm8250 \
        --base 0x0 \
        --second_offset 0x00f00000 \
        --cmdline "clk_ignore_unused pd_ignore_unused root=UUID=${new_rootfs_image_uuid}" \
        --kernel_offset 0x8000 \
        --ramdisk_offset 0x1000000 \
        --tags_offset 0x100 \
        --pagesize 4096 \
        -o /boot/armbian-kernel-${panel_type}.img
rm -f /tmp/Image.gz /tmp/Image.gz-dtb-${panel_type}
