#!/bin/bash
#
# Configuration

DEST=/dev/sda1
FORMAT=yes

#
clear_console
figlet -f banner "warning"
#echo "Edit file !!!"; exit 0; # DELETE OR COMMENT THIS LINE TO CONTINUE
#
#
# Do not modify anything below
#

# Check if user is root
if [ $(id -u) != "0" ]; then
    echo "Error: You must be root to run this script."
    exit 1
fi

cat > .install-exclude <<EOF
/dev/*
/proc/*
/sys/*
/media/*
/mnt/*
/run/*
/tmp/*
/boot/*
/root/*
EOF

clear_console
figlet -f banner "warning"
echo "

This script might erase your Hard drive and copy content of SD card to it

"

echo -n "Proceed (y/n)? (default: y): "
read nandinst

if [ "$nandinst" == "n" ]
then
  exit 0
fi


if [ "$FORMAT" == "yes" ]
then
  mkfs.ext4 $DEST
fi

mount $DEST /mnt

sed -e 's,root=\/dev\/mmcblk0p1,root='"$DEST"',g' -i /boot/uEnv.ct
sed -e 's,root=\/dev\/mmcblk0p1,root='"$DEST"',g' -i /boot/uEnv.cb2

echo "Creating hard drive rootfs ... up to 5 min"
rsync -aH --exclude-from=.install-exclude  /  /mnt
# change fstab
sed -e 's,\/dev\/mmcblk0p1,'"$DEST"',g' -i /mnt/etc/fstab
umount /mnt
figlet -f banner "warning"
echo "All done. Press a key to reboot! System needs SD card for boot process! Can't boot directly from hard drive"
rm .install-exclude
read konec
reboot
