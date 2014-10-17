#!/bin/bash
#
# Configuration

DEST=sda1
FORMAT=yes

#
clear_console



if [[ -z $(cat /proc/partitions | grep $DEST) ]]; then 
	echo "Device not partitioned";
	exit 0
fi

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

MODEL=$(hdparm -i /dev/sda | perl -n -e 'print "$1\n" if (m/model=(.+?),/i);')

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
echo -e "

This script will erase first partition of your hard drive \e[31m($MODEL)\e[39m and copy content of SD card to it

"

echo -n "Proceed (y/n)? (default: y): "
read nandinst

if [ "$nandinst" == "n" ]
then
  exit 0
fi


if [ "$FORMAT" == "yes" ]
then
  mkfs.ext4 /dev/$DEST
fi

mount /dev/$DEST /mnt

if [ -f "/boot/uEnv.ct" ]; then sed -e 's,root=\/dev\/mmcblk0p1,root='"\/dev\/$DEST"',g' -i /boot/uEnv.ct ; fi
if [ -f "/boot/uEnv.cb2" ]; then sed -e 's,root=\/dev\/mmcblk0p1,root='"\/dev\/$DEST"',g' -i /boot/uEnv.cb2; fi
if [ -f "/boot/uEnv.txt" ]; then sed -e 's,root=\/dev\/mmcblk0p1,root='"\/dev\/$DEST"',g' -i /boot/uEnv.txt; fi


echo "Creating hard drive rootfs ... can take several minutes to finish!"
rsync -aH --exclude-from=.install-exclude  /  /mnt
# change fstab
sed -e 's,\/dev\/mmcblk0p1,'"\/dev/$DEST"',g' -i /mnt/etc/fstab
sed -i "s/data=writeback,//" /mnt/etc/fstab

umount /mnt
figlet -f banner "warning"
echo "All done. Press a key to reboot! System needs SD card for boot process! Can't boot directly from hard drive"
rm .install-exclude
read konec
reboot
