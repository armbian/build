#!/bin/bash
set -ex
new_rootfs_image_uuid=$(sed -e 's/^.*root=UUID=//' -e 's/ .*$//' < /proc/cmdline)
gzip -c /boot/vmlinuz-*-sm8550-arm64 > /tmp/Image.gz

cat /tmp/Image.gz /usr/lib/linux-image-*-sm8550-arm64/qcom/qcs8550-ayn-odin2-hypdtbo.dtb > /tmp/Image.gz-dtb

source /boot/armbianEnv.txt
/usr/bin/mkbootimg \
        --kernel /tmp/Image.gz-dtb \
        --ramdisk /boot/initrd.img-*-sm8550-arm64 \
        --base 0x0 \
        --second_offset 0x00f00000 \
        --cmdline "clk_ignore_unused pd_ignore_unused panic=30 audit=0 allow_mismatched_32bit_el0 rw mem_sleep_default=s2idle root=UUID=${new_rootfs_image_uuid}" \
        --kernel_offset 0x8000 \
        --ramdisk_offset 0x1000000 \
        --tags_offset 0x100 \
        --pagesize 4096 \
        -o /boot/armbian-kernel.img
rm -f /tmp/Image.gz /tmp/Image.gz-dtb
