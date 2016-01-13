#!/bin/bash
#
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
#
# www.igorpecovnik.com / images + support
#
# NAND, SATA and USB Armbian installer
# nand boot za a10: git clone -b dev/a10-nand-ext4 https://github.com/mmplayer/u-boot-sunxi --depth 1
# Should work with: Cubietruck, Cubieboards, BananaPi, Olimex Lime+Lime2+Micro, Hummingboard, ...
#


# Target sata drive
CWD="/usr/lib/nand-sata-install"
EX_LIST="${CWD}/exclude.txt"
backtitle="Armbian install script, http://www.armbian.com | Author: Igor Pecovnik"
title="NAND, SATA and USB Armbian installer"


#-----------------------------------------------------------------------------------------------------------------------
# Main function for creating boot and root file system
#
# Accept two device parameters: $1 = boot, $2 = root (Example: create_armbian "/dev/nand1" "/dev/sda3")
#-----------------------------------------------------------------------------------------------------------------------
create_armbian ()
{

# unmount devices
umountdevice "$1"; umountdevice "$2"

# create mount points, mount and clean
mkdir -p /mnt/bootfs /mnt/rootfs
[ -n "$1" ] && mount $1 /mnt/bootfs
[ -n "$2" ] && mount $2 /mnt/rootfs
rm -rf /mnt/bootfs/* /mnt/rootfs/*

# calculate usage and see if it fits on destination
USAGE=$(df -BM | grep ^/dev | head -1 | awk '{print $3}' | tr -cd '[0-9]. \n')
DEST=$(df -BM | grep ^/dev | grep /mnt/rootfs | awk '{print $4}' | tr -cd '[0-9]. \n')
if [ $USAGE -gt $DEST ]; then
	dialog --title "$title" --backtitle "$backtitle"  --colors --infobox\
	"\n\Z1Partition too small.\Zn Needed: $USAGE Mb Avaliable: $DEST Mb" 5 60
	umountdevice "$1"; umountdevice "$2"
	exit 1
fi

# creating nand boot. Copy precompiled uboot
rsync -aqc $BOOTLOADER/* /mnt/bootfs

# count files is needed for progress bar
dialog --title "$title" --backtitle "$backtitle" --infobox "\nCounting files ... few seconds." 5 60
TODO=$(rsync -ahvrltDn --delete --stats --exclude-from=$EX_LIST /  /mnt/rootfs |grep "Number of files:"|awk '{print $4}' | tr -d '.,')

# creating rootfs
rsync -avrltD  --delete --exclude-from=$EX_LIST  /  /mnt/rootfs | nl | awk '{ printf "%.0f\n", 100*$1/"'"$TODO"'" }' \
| dialog --backtitle "$backtitle"  --title "$title" --gauge "\n Creating rootfs on $2 ($USAGE Mb). Please wait!" 8 60

# creating fstab - root partition
sed -e 's,\/dev\/mmcblk0p.,'"$2"',g' -i /mnt/rootfs/etc/fstab

# creating fstab, kernel and boot script for NAND partition
if [ -n "$1" ]; then
REMOVESDTXT="and remove SD to boot from NAND"
sed -i '/boot/d' /mnt/rootfs/etc/fstab
echo "$1 /boot vfat	defaults 0 0" >> /mnt/rootfs/etc/fstab
dialog --title "$title" --backtitle "$backtitle" --infobox "\nConverting kernel ... few seconds." 5 60
mkimage -A arm -O linux -T kernel -C none -a "0x40008000" -e "0x40008000" -n "Linux kernel" -d \
/boot/zImage /mnt/bootfs/uImage >/dev/null 2>&1
cp /boot/script.bin /mnt/bootfs/
cat > /mnt/bootfs/uEnv.txt <<EOF
console=ttyS0,115200
root=$2 rootwait
extraargs=console=tty1 hdmi.audio=EDID:0 disp.screen0_output_mode=EDID:0 consoleblank=0 loglevel=1
EOF
sync
[[ $DEVICE_TYPE = "a20" ]] && echo "machid=10bb" >> /mnt/bootfs/uEnv.txt
umountdevice "/dev/nand"
tune2fs -o journal_data_writeback /dev/nand2 >/dev/null 2>&1
tune2fs -O ^has_journal /dev/nand2 >/dev/null 2>&1
e2fsck -f /dev/nand2 >/dev/null 2>&1
elif [ -f /boot/boot.cmd ]; then
	sed -e 's,root=\/dev\/mmcblk0p.,root='"$2"',g' -i /boot/boot.cmd
	mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
	mkdir -p /mnt/rootfs/media/mmc/boot
	echo "/dev/mmcblk0p1        /media/mmc   ext4    defaults        0       0" >> /mnt/rootfs/etc/fstab
	echo "/media/mmc/boot   /boot   none    bind        0       0" >> /mnt/rootfs/etc/fstab
	sed -i "s/data=writeback,//" /mnt/rootfs/etc/fstab
fi
umountdevice "/dev/sda"
}


#-----------------------------------------------------------------------------------------------------------------------
# Let's unmount all targets 
#
# Accept device as parameter: for example /dev/sda unmounts all their mounts
#-----------------------------------------------------------------------------------------------------------------------
umountdevice() {
sync
if [ -n "$1" ]; then
	device=$1; device="${device//[0-9]*/}"
	for n in ${device}*; do
		if [ "${device}" != "$n" ]; then
			if mount|grep -q ${n}; then
				umount -l $n >/dev/null 2>&1
			fi
		fi
	done
fi
}


#-----------------------------------------------------------------------------------------------------------------------
# Formatting NAND
#
# No parameters. Fixed solution.
#-----------------------------------------------------------------------------------------------------------------------
formatnand(){
dialog --title "$title" --backtitle "$backtitle"  --infobox "\nFormating ... up to one minute." 5 60
if [[ "$DEVICE_TYPE" = "a20" ]]; then
(echo y;) | nand-part -f a20 /dev/nand 65536 'bootloader 65536' 'linux 0' >/dev/null 2>&1
else
(echo y;) | nand-part -f a10 /dev/nand 65536 'bootloader 65536' 'linux 0' >/dev/null 2>&1
fi
mkfs.vfat /dev/nand1 >/dev/null 2>&1
mkfs.ext4 /dev/nand2 >/dev/null 2>&1
}


#-----------------------------------------------------------------------------------------------------------------------
# Formatting SATA/USB
#
# Accept device as parameter: for example /dev/sda3
#-----------------------------------------------------------------------------------------------------------------------
formatsata(){
dialog --title "$title" --backtitle "$backtitle"  --infobox "\nPartitioning and formating ... up to one minute." 5 60
mkfs.ext4 $1 >/dev/null 2>&1
}


#-----------------------------------------------------------------------------------------------------------------------
# Choose target SATA/USB partition.
#-----------------------------------------------------------------------------------------------------------------------
function checksatatarget
{
IFS=" "
SataTargets=$(cat /proc/partitions | grep sd | awk '{print "/dev/"$4}' | grep -E '[0-9]{1,4}' | nl | xargs echo -n)
if [[ "$SataTargets" == "" ]]; then
	dialog --title "$title" --backtitle "$backtitle"  --colors --infobox\
	"\n\Z1There are no avaliable partitions. Please create them.\Zn" 5 60
	exit 1
fi
SataOptions=($SataTargets)
SataCmd=(dialog --title "Select destination:" --backtitle "$backtitle" --menu "\n$infos" 10 60 16)
SataChoices=$("${SataCmd[@]}" "${SataOptions[@]}" 2>&1 >/dev/tty)
if [ $? -ne 0 ]; then exit 1; fi
SDA_ROOT_PART=${SataOptions[(2*$SataChoices)-1]}
}


#-----------------------------------------------------------------------------------------------------------------------
# Show warning, TEXT is a parameter
#-----------------------------------------------------------------------------------------------------------------------
function ShowWarning
{
# show big warning
dialog --title "$title" --backtitle "$backtitle" --cr-wrap --colors --yesno " \Z1$(toilet -f mono12 WARNING)\Zn\n$1" 17 74
if [ $? -ne 0 ]; then exit 1; fi
}


########################################################################################################################
#
# Prepare main selection
#
########################################################################################################################


#-----------------------------------------------------------------------------------------------------------------------
# This tool must run under root
#-----------------------------------------------------------------------------------------------------------------------
if [[ ${EUID} -ne 0 ]]; then
	echo "This tool must run as root. Exiting ..." 
	exit 1
fi


#-----------------------------------------------------------------------------------------------------------------------
# Downloading dependencies
#-----------------------------------------------------------------------------------------------------------------------
if [ $(dpkg-query -W -f='${Status}' dialog 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
echo "Downloading dependencies ... please wait"
apt-get install -qq -y dialog >/dev/null 2>&1
fi 


#-----------------------------------------------------------------------------------------------------------------------
# Check if we run it from SD card
#-----------------------------------------------------------------------------------------------------------------------
if [[ "$(sed -n 's/^DEVNAME=//p' /sys/dev/block/$(mountpoint -d /)/uevent)" != mmcblk* ]]; then
dialog --title "$title" --backtitle "$backtitle"  --colors --infobox "\n\Z1This tool must run from SD-card!\Zn" 5 42
exit 1
fi


#-----------------------------------------------------------------------------------------------------------------------
# Main selection
#-----------------------------------------------------------------------------------------------------------------------

if cat /proc/cpuinfo | grep -q 'sun4i'; then DEVICE_TYPE="a10"; else DEVICE_TYPE="a20"; fi 	# Determine device
BOOTLOADER="${CWD}/${DEVICE_TYPE}/bootloader"											# Define bootloader
nandcheck=$(grep nand /proc/partitions)													# check NAND 
satacheck=$(grep sd /proc/partitions)													# check SATA/USB
IFS="'"
options=()
[[ -n "$nandcheck" ]] 							&& options=(${options[@]} 1 'Boot from NAND - system on NAND')
[[ -n "$nandcheck" && -n "$satacheck" ]]		&& options=(${options[@]} 2 'Boot from NAND - system on SATA or USB')
[[ -n "$satacheck" ]]							&& options=(${options[@]} 3 'Boot from SD   - system on SATA or USB')
[[ ${#options[@]} -eq 0 ]] 						&& dialog --title "$title" --backtitle "$backtitle"  --colors --infobox\
												"\n\Z1There are no targets. Please check your drives.\Zn" 5 60 && exit 1

cmd=(dialog --title "Choose an option:" --backtitle "$backtitle" --menu "\n" 9 60 3)
choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
if [ $? -ne 0 ]; then
	    exit 1
fi

for choice in $choices
do
    case $choice in
        1)
			title="NAND install"
			command="Power off"
			ShowWarning "This script will erase your device /dev/nand. Continue?"
			formatnand
			create_armbian "/dev/nand1" "/dev/nand2"
            ;;
        2)
			title="NAND boot / SATA root install"
			command="Power off"
			checksatatarget
			ShowWarning "This script will erase your device /dev/nand and $SDA_ROOT_PART. Continue?"
			formatnand
			formatsata "$SDA_ROOT_PART"
			create_armbian "/dev/nand1" "$SDA_ROOT_PART"
            ;;
        3)
			title="SD boot / SATA root install"
			command="Reboot"
			checksatatarget
			ShowWarning "This script will erase your device $SDA_ROOT_PART. Continue?"
			formatsata "$SDA_ROOT_PART"
			create_armbian "" "$SDA_ROOT_PART"
            ;;
    esac
done

dialog --title "$title" --backtitle "$backtitle"  --yes-label "$command" --no-label "Exit" \
--yesno "\nAll done. $command $REMOVESDTXT" 7 60
if [ $? -eq 0 ]; then "$(echo ${command,,} | sed 's/ //')"; fi