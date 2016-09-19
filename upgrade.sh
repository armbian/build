#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#


BOARD=""
RELEASE=$(lsb_release -cs)
if [[ "$RELEASE" == "sid" ]]; then RELEASE="jessie"; fi
if [[ "$RELEASE" == "testing" ]]; then RELEASE="jessie"; fi
backtitle="Armbian install script, http://www.armbian.com | Author: Igor Pecovnik"
title="Armbian universal installer 2015.11"


#-----------------------------------------------------------------------------------------------------------------------
# Show warning at start
#-----------------------------------------------------------------------------------------------------------------------
display_warning()
{
read -r -d '' MOJTEXT << EOM
1. Please do a backup even if the script doesn't plan to ruin anything critical.

2. If you choose the wrong board you might end up with a non-bootable system.

3. We are going to remove current kernel package together with headers, firmware and board definitions.

4. The script will also conduct apt-get upgrade so all packages will be upgraded.

5. Where possible you can upgrade/downgrade kernel from legacy to vanilla and vice versa.

6. The whole process takes at least 8 minutes on a fresh image to 30 minutes if you upgrade from other system.

7. You might need to power cycle the board.
EOM
dialog --title "$title" --backtitle "$backtitle" --cr-wrap --colors --yesno " \Z1$(toilet -f mono12 WARNING)\Z0\n$MOJTEXT" 36 74
if [ $? -ne 0 ]; then exit 1; fi
}


#-----------------------------------------------------------------------------------------------------------------------
# Create boot scripts for Allwinner boards
#-----------------------------------------------------------------------------------------------------------------------
create_boot_script ()
{
[ -f "/boot/boot.cmd" ] && cp /boot/boot.cmd /boot/boot.cmd.backup
cat > /boot/boot.cmd <<EOT
setenv bootargs "console=tty1 root=$rootdevice rootwait rootfstype=ext4 sunxi_ve_mem_reserve=0 sunxi_g2d_mem_reserve=0 \
sunxi_no_mali_mem_reserve sunxi_fb_mem_reserve=16 hdmi.audio=EDID:0 disp.screen0_output_mode=1920x1080p60 panic=10 \
consoleblank=0 enforcing=0 loglevel=1"
#-----------------------------------------------------------------------------------------------------------------------
# Boot loader script to boot with different boot methods for old and new kernel
#-----------------------------------------------------------------------------------------------------------------------
if ext4load mmc 0 0x00000000 /boot/.next || fatload mmc 0 0x00000000 .next
then
# sunxi mainline kernel
#-----------------------------------------------------------------------------------------------------------------------
ext4load mmc 0 0x49000000 /boot/dtb/\${fdtfile} || fatload mmc 0 0x49000000 /dtb/\${fdtfile}
ext4load mmc 0 0x46000000 /boot/zImage || fatload mmc 0 0x46000000 zImage
env set fdt_high ffffffff
bootz 0x46000000 - 0x49000000
#-----------------------------------------------------------------------------------------------------------------------
else
# sunxi android kernel
#-----------------------------------------------------------------------------------------------------------------------
ext4load mmc 0 0x43000000 /boot/script.bin || fatload mmc 0 0x43000000 script.bin
ext4load mmc 0 0x48000000 /boot/zImage || fatload mmc 0 0x48000000 zImage
bootz 0x48000000
#-----------------------------------------------------------------------------------------------------------------------
fi
# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
EOT
mkimage -C none -A arm -T script -d  /boot/boot.cmd  /boot/boot.scr >/dev/null 2>&1
}


#-----------------------------------------------------------------------------------------------------------------------
# Install packeges and repository
#-----------------------------------------------------------------------------------------------------------------------
install_repo ()
{
dialog --title "$title" --backtitle "$backtitle"  --infobox "\nAdding repository and running pkg list update." 5 50
# remove system hostapd
apt-get -f -qq install
apt-get clean
apt-get -y -qq remove hostapd
if [ $? -ne 0 ]; then
	    dialog --title "$title" --backtitle "$backtitle"  --infobox "\nError in apt-get. Can not continue." 5 40
		exit 1
fi
# move armbian to separate list and remove others
sed -i '/armbian/d' /etc/apt/sources.list
if [ -f "/etc/apt/sources.list.d/bananian.list" ]; then
rm -f /etc/apt/sources.list.d/bananian.list
rm -f /etc/kernel/postinst.d/bananian-kernel-postinst
chsh -s /bin/bash
echo "Armbian lite" > /etc/motd
echo "" >> /etc/motd
fi
if [ ! -f "/etc/apt/sources.list.d/armbian.list" ]; then
	echo -e "[\e[0;32m o.k. \x1B[0m] Updating package list. Please wait"
	echo "deb http://apt.armbian.com $RELEASE main" > /etc/apt/sources.list.d/armbian.list
	apt-key adv --keyserver keys.gnupg.net --recv-keys 0x93D6889F9F0E78D5 >/dev/null 2>&1
	apt-get update >/dev/null 2>&1
fi
}


get_hardware_info ()
#-----------------------------------------------------------------------------------------------------------------------
# determine root and boot partitions, arhitecture, cpu, ...
#-----------------------------------------------------------------------------------------------------------------------
{

# arhitecture
ARCH=$(lscpu | grep Architecture  | awk '{print $2}')
if [[ "$ARCH" != arm* ]]; then
	echo -e "[\e[0;31m error \x1B[0m] Architecture not supported"; exit;
fi

# CPU
HARDWARE=$(cat /proc/cpuinfo | grep Hardware | awk '{print $3}')
if [[ !( "$HARDWARE" == "sun7i" || "$HARDWARE" == "Allwinner" || "$HARDWARE" == "sun4i" ) ]]; then
	echo -e "[\e[0;31m error \x1B[0m] Unsupported hw"; exit;
fi

# boot partition
bootdevice="/dev/mmcblk0p1";

# if mmc is not present than boot can only be nand1
if [[ "$(grep nand /proc/partitions)" != "" && "$(grep mmc /proc/partitions)" == "" ]]; then
bootdevice="/dev/nand1";
fi

# root partition
root_device=$(mountpoint -d /)
for file in /dev/* ; do
CURRENT_DEVICE=$(printf "%d:%d" $(stat --printf="0x%t 0x%T" $file))
if [ $CURRENT_DEVICE = $root_device ]; then
	rootdevice=$file
	break;
fi
done
rootdevice="/dev/"$(sed -n 's/^DEVNAME=//p' /sys/dev/block/$(mountpoint -d /)/uevent)
}


mount_boot_device ()
#-----------------------------------------------------------------------------------------------------------------------
# mount boot device
#-----------------------------------------------------------------------------------------------------------------------
{
if [[ "$bootdevice" == "/dev/mmcblk0p1" && "$rootdevice" != "/dev/mmcblk0p1" ]]; then
	umount /boot /media/mmc
	mkdir -p /media/mmc/boot
	mount /dev/mmcblk0p1 /media/mmc/
    if [ -d "/media/mmc/boot/" ]; then
		mount --bind /media/mmc/boot/ /boot/
	else
		mount --bind /media/mmc /boot/
	fi
fi
if [[ "$bootdevice" == "/dev/nand1" ]]; then
	umount /boot /mnt
	mount /dev/nand1 /boot
fi
}


select_boards ()
#-----------------------------------------------------------------------------------------------------------------------
# This might be changed once with board detection which is already very accurate
#-----------------------------------------------------------------------------------------------------------------------
{

if [ -z "$BOARD" ]; then
	IFS=" "
	Options="Cubieboard A10 Cubieboard2 A20 Cubietruck A20 Lime-A10 A10 Lime \
A20 Lime2 A20 Micro A20 Bananapipro A20 Lamobo-R1 A20 Orangepi A20 Pcduino3nano A20"
	BoardOptions=($Options);
	BoardCmd=(dialog --title "Choose a board:" --backtitle "$backtitle" --menu "\n$infos" 20 60 26)
	BoardChoices=$("${BoardCmd[@]}" "${BoardOptions[@]}" 2>&1 >/dev/tty)
	BOARD=${BoardChoices,,}
fi
# exit the script on cancel
if [ "$BOARD" == "" ]; then echo "ERROR: You have to choose a board"; exit; fi


if [ -z "$BRANCH" ]; then
	IFS="'"
	declare -a Options=("legacy'3.4.x - 3.14.x most supported'vanilla'4.x Vanilla from www.kernel.org");
	# Exceptions
	if [[ $BOARD == "cubox-i" || $BOARD == "udoo-neo" || "$bootdevice" == "/dev/nand1" ]]; then
		declare -a Options=("legacy'3.4.x - 3.14.x most supported");
	fi
	BoardOptions=($Options);
	BoardCmd=(dialog --title "Choose a board:" --backtitle "$backtitle" --menu "\n$infos" 10 60 16)
	BoardChoices=$("${BoardCmd[@]}" "${BoardOptions[@]}" 2>&1 >/dev/tty)
	BRANCH=${BoardChoices,,}
fi

# exit the script on cancel
if [ "$BRANCH" == "" ]; then echo "ERROR: You have to choose a branch"; exit; fi


if [[ $BRANCH == "vanilla" ]] ; then
	ROOT_BRACH="-next"
	else
	ROOT_BRACH=""
fi

case $BOARD in
bananapipro | lamobo-r1 | orangepi | orangepimini)
LINUXFAMILY="sun7i"
if [[ $BRANCH == "vanilla" ]] ; then LINUXFAMILY="sunxi"; fi
;;
cubox-i)
LINUXFAMILY="cubox"
;;
cubieboard | lime-a10)
LINUXFAMILY="sun4i"
if [[ $BRANCH == "vanilla" ]] ; then LINUXFAMILY="sunxi"; fi
;;
udoo | udoo-neo)
LINUXFAMILY="udoo"
;;
*)
LINUXFAMILY="sun7i"
if [[ $BRANCH == "vanilla" ]] ; then LINUXFAMILY="sunxi"; fi
;;
esac

if [[ $BOARD == "cubox-i" || $BOARD == udoo* || $BRANCH == "vanilla" ]];
	then PACKETS="linux-dtb$ROOT_BRACH-$LINUXFAMILY";
fi

PACKETS="linux-image$ROOT_BRACH-$LINUXFAMILY linux-firmware-image$ROOT_BRACH-$LINUXFAMILY \
linux-u-boot-$BOARD$ROOT_BRACH linux-headers$ROOT_BRACH-$LINUXFAMILY linux-$RELEASE-root$ROOT_BRACH-$BOARD $PACKETS"
}


remove_old ()
#-----------------------------------------------------------------------------------------------------------------------
# Delete previous kernel
#-----------------------------------------------------------------------------------------------------------------------
{
clear
dialog --title "$title" --backtitle "$backtitle"  --infobox "\nRemoving conflicting packages..." 5 41
aptitude remove ~nlinux-dtb --quiet=100 >> upgrade.log
aptitude remove ~nlinux-u-boot --quiet=100 >> upgrade.log
aptitude remove ~nlinux-image --quiet=100 >> upgrade.log
aptitude remove ~nlinux-headers --quiet=100 >> upgrade.log
aptitude remove ~nlinux-firmware --quiet=100 >> upgrade.log
aptitude remove ~nlinux-$RELEASE-root --quiet=100 >> upgrade.log
}


install_new ()
#-----------------------------------------------------------------------------------------------------------------------
# install new one
#-----------------------------------------------------------------------------------------------------------------------
{
IFS=" "
apt-get $1 -y install $PACKETS 2>&1 | dialog --title "$title" --backtitle "$backtitle" --progressbox "$2" 20 80
if [ $? -ne 0 ]; then
dialog --title "$title" --backtitle "$backtitle"  --infobox "\nError during new packages download." 5 41
exit 1;
fi
}


#-----------------------------------------------------------------------------------------------------------------------
#
# Program start
#
#-----------------------------------------------------------------------------------------------------------------------
# This tool must run under root
#-----------------------------------------------------------------------------------------------------------------------
if [[ ${EUID} -ne 0 ]]; then
	echo "This tool must be run as root. Exiting..."
	exit 1
fi


#-----------------------------------------------------------------------------------------------------------------------
# Downloading dependencies
#-----------------------------------------------------------------------------------------------------------------------
if [[ $(dpkg-query -W -f='${Status}' dialog 2>/dev/null | grep -c "ok installed") -eq 0 || \
	  $(dpkg-query -W -f='${Status}' u-boot-tools 2>/dev/null | grep -c "ok installed") -eq 0 || \
	  $(dpkg-query -W -f='${Status}' debconf-utils 2>/dev/null | grep -c "ok installed") -eq 0 || \
	  $(dpkg-query -W -f='${Status}' lsb-release 2>/dev/null | grep -c "ok installed") -eq 0 || \
	  $(dpkg-query -W -f='${Status}' aptitude 2>/dev/null | grep -c "ok installed") -eq 0 \
	]]; then
echo "Downloading dependencies... please wait"
apt-get install -qq -y dialog u-boot-tools debconf-utils lsb-release aptitude fake-hwclock >/dev/null 2>&1
fi

display_warning
install_repo
get_hardware_info
mount_boot_device
create_boot_script
select_boards
install_new "-d" "Downloading packages..."
remove_old
install_new "" "Installing packages..."


apt-get -y upgrade 2>&1 | dialog --title "$title" --backtitle "$backtitle" --progressbox "System upgrade" 20 80

[[ "$bootdevice" == "/dev/nand1" ]] && sed -e 's,script=.*,script=script.bin,g' -i /boot/uEnv.txt
ln -sf /boot/bin/$BOARD.bin /boot/script.bin || cp /boot/bin/$BOARD.bin /boot/script.bin

dialog --title "$title" --backtitle "$backtitle"  --yes-label "Reboot" --no-label "Exit" \
--yesno "\nAll done." 7 60
if [ $? -eq 0 ]; then reboot; fi

echo "Visit: forum.armbian.com in case of trouble or just for fun ;)"
echo ""
