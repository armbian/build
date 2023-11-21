#!/bin/bash

c=0
cd /dev
for file in `ls mmcblk*`
do
    filelist[$c]=$file
    ((c++))
done

ROOT_DEV=/dev/${filelist[0]}

BOOT_NUM=1
ROOT_NUM=2

ROOTFS_START=532480

# fdisk
sudo fdisk "$ROOT_DEV" << EOF
p
d
$ROOT_NUM
n
p
$ROOT_NUM
$ROOTFS_START

y
w
EOF

sudo resize2fs /dev/${filelist[$c-1]}
unset filelist

#-----------------
# username=biqu
# sudo usermod -a -G root $username         # add biqu to root group
# sudo gpasswd -d biqu root     # remove biqu from root group

sudo sed -i '/^.\/extend_fs.sh/s/^/#/' /boot/scripts/btt_init.sh
