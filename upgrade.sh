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

#--------------------------------------------------------------------------------------------------------------------------------
display_warning()
{
read -r -d '' MOJTEXT << EOM
1. Please do a backup even the script doesn't plan to ruin anything critical.

2. If you choose wrong board you might end up with not bootable system.

3. We are going to remove current kernel package together with headers, firmware and board definitions.

4. The script will also conduct apt-get upgrade so all packages will be upgraded.

5. Where possible you can upgrade/downgrade kernel from legacy to vanilla and vice versa.

6. The whole process takes at least 8 minutes on a fresh image to 30 minutes if you upgrade from other system.

7. You might need to power cycle the board.
EOM
whiptail --title "Armbian upgrade script 1.3" --msgbox "$MOJTEXT" 25 60
}
create_boot_script ()
{
# create boot script $1 = where $2 root device
cat > /boot/boot.cmd <<EOT
setenv bootargs console=tty1 root=$rootdevice rootwait rootfstype=ext4 sunxi_ve_mem_reserve=0 sunxi_g2d_mem_reserve=0 sunxi_no_mali_mem_reserve sunxi_fb_mem_reserve=16 hdmi.audio=EDID:0 disp.screen0_output_mode=1920x1080p60 panic=10 consoleblank=0 enforcing=0 loglevel=1
#--------------------------------------------------------------------------------------------------------------------------------
# Boot loader script to boot with different boot methods for old and new kernel
#--------------------------------------------------------------------------------------------------------------------------------
if ext4load mmc 0 0x00000000 /boot/.next || fatload mmc 0 0x00000000 .next
then
# sunxi mainline kernel
#--------------------------------------------------------------------------------------------------------------------------------
ext4load mmc 0 0x49000000 /boot/dtb/\${fdtfile} || fatload mmc 0 0x49000000 /dtb/\${fdtfile}
ext4load mmc 0 0x46000000 /boot/zImage || fatload mmc 0 0x46000000 zImage
env set fdt_high ffffffff
bootz 0x46000000 - 0x49000000
#--------------------------------------------------------------------------------------------------------------------------------
else
# sunxi android kernel
#--------------------------------------------------------------------------------------------------------------------------------
ext4load mmc 0 0x43000000 /boot/script.bin || fatload mmc 0 0x43000000 script.bin
ext4load mmc 0 0x48000000 /boot/zImage || fatload mmc 0 0x48000000 zImage
bootz 0x48000000
#--------------------------------------------------------------------------------------------------------------------------------
fi
# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr 
EOT
mkimage -C none -A arm -T script -d  /boot/boot.cmd  /boot/boot.scr
}
install_packets_and_repo ()
{
# we need this
apt-get -y -qq install u-boot-tools debconf-utils lsb-release pv aptitude
apt-get -y -qq remove hostapd
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
	echo "deb http://apt.armbian.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/armbian.list
	apt-key adv --keyserver keys.gnupg.net --recv-keys 0x93D6889F9F0E78D5 >/dev/null 2>&1
	apt-get update >/dev/null 2>&1
fi
}
get_hardware_info ()
# determine root and boot partitions
{
ARCH=$(lscpu | grep Architecture  | awk '{print $2}')
HARDWARE=$(cat /proc/cpuinfo | grep Hardware | awk '{print $3}')
SOURCE=$(dmesg |grep root)
SOURCE=${SOURCE#"${SOURCE%%root=*}"}
SOURCE=`echo $SOURCE| cut -d' ' -f 1`
SOURCE="${SOURCE//root=/}"
if [[ "$ARCH" != arm* ]]; then echo -e "[\e[0;31m error \x1B[0m] Architecture not supported"; fi
if [[ "$HARDWARE" != "sun7i" && "$HARDWARE" != "Allwinner" ]]; then echo -e "[\e[0;31m error \x1B[0m] Unsupported hw"; fi
bootdevice="/dev/mmcblk0p1";
i=0
if [[ "$(grep nand /proc/partitions)" != "" && "$(grep mmc /proc/partitions)" == "" ]]; then bootdevice="/dev/nand1"; fi
if [ "$(grep mmc /proc/partitions)" != "" ]; then get_root_device mmc p; i=$[$i+1];fi
root[$i]=$rootdevice
if [ "$(grep sda /proc/partitions)" != "" ]; then get_root_device sda; i=$[$i+1];fi
root[$i]=$rootdevice
# if we have both options ask to confirm
if [[ "$SOURCE" == "${root[1]}" ]]; then default="--defaultno"; fi 
if [[ "${root[0]}" != "" && "${root[1]}" != "" ]]; then
	if (whiptail $default --yesno "I detected the default settings. Just make sure." --title "Running from ?" \
	--yes-button "${root[0]}" --no-button "${root[1]}" 7 48); 
		then rootdevice=${root[0]};
		else rootdevice=${root[1]};
	fi
fi
}
get_root_device ()
{
rootdevice="/dev/"$(lsblk -idn -o NAME | grep $1)
partitions=$(($(fdisk -l $rootdevice | grep $rootdevice | wc -l)-1))
rootdevice="/dev/"$(lsblk -idn -o NAME | grep $1)$2$partitions
}
mount_boot_device ()
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
	mount /dev/nand1 /mnt
fi
}
select_boards ()
{
backtitle="Armbian upgrade"
if [ "$BOARD" == "" ]; then
	BOARDS="AW-som-a20 A20 Cubieboard A10 Cubieboard2 A20 Cubietruck A20 Lime-A10 A10 Lime A20 Lime2 A20 Micro A20 Bananapi A20 \
    Lamobo-R1 A20 Orangepi A20 Pcduino3nano A20 Cubox-i imx6 Udoo imx6";
	MYLIST=`for x in $BOARDS; do echo $x ""; done`
	whiptail --title "Choose a board" --backtitle "$backtitle" --menu "\nWhich one?" 24 30 16 $MYLIST 2>results    
	BOARD=$(<results)
	BOARD=${BOARD,,}
	rm results
fi
# exit the script on cancel
if [ "$BOARD" == "" ]; then echo "ERROR: You have to choose one board"; exit; fi

IFS=";"
declare -a MYARRAY=('default' '3.4.x - 3.14.x most supported' 'next' '4.x Vanilla from www.kernel.org');
# Exceptions
if [[ $BOARD == "cubox-i" || $BOARD == "udoo-neo" || "$bootdevice" == "/dev/nand1" ]]; then declare -a MYARRAY=('default' '3.4.x - 3.14.x most supported'); fi
if [[ $BOARD == "udoo" ]]; then declare -a MYARRAY=('next' '4.x Vanilla from www.kernel.org'); fi

MYPARAMS=( --title "Where to upgrade" --backtitle $backtitle --menu "\n Board $BOARD:" 11 60 2 )
	i=0
	j=1
	while [[ $i -lt ${#MYARRAY[@]} ]]
	do
        MYPARAMS+=( "${MYARRAY[$i]}" "         ${MYARRAY[$j]}" )
        i=$[$i+2]
		j=$[$j+2]
	done
	whiptail "${MYPARAMS[@]}" 2>results  
	BRANCH=$(<results)
	rm results
	unset MYARRAY

# exit the script on cancel
if [ "$BRANCH" == "" ]; then echo "ERROR: You have to choose one branch"; exit; fi


if [[ $BRANCH == "next" ]] ; then
	ROOT_BRACH="-next"
	else
	ROOT_BRACH=""
fi 

case $BOARD in
bananapi | bananapipro | lamobo-r1 | orangepi | orangepimini)
LINUXFAMILY="banana"
if [[ $BRANCH == "next" ]] ; then LINUXFAMILY="sunxi"; fi
;;
cubox-i)
LINUXFAMILY="cubox"
;;
udoo | udoo-neo)
LINUXFAMILY="udoo"
;;
*)
LINUXFAMILY="sunxi"
;;
esac
 }
remove_old ()
{
clear
whiptail --title "Armbian upgrade" --infobox "Removing old kernel packages ... check upgrade.log" 7 60
aptitude remove ~nlinux-dtb --quiet=100 >> upgrade.log
aptitude remove ~nlinux-u-boot --quiet=100 >> upgrade.log
aptitude remove ~nlinux-image --quiet=100 >> upgrade.log
aptitude remove ~nlinux-headers --quiet=100 >> upgrade.log
aptitude remove ~nlinux-firmware --quiet=100 >> upgrade.log
aptitude remove ~nlinux-$(lsb_release -cs)-root --quiet=100 >> upgrade.log
}
install_new ()
{
PACKETS="  "
if [[ $BOARD == "cubox-i" || $BOARD == udoo* || $BRANCH == "next" ]]; then PACKETS="linux-dtb$ROOT_BRACH-$LINUXFAMILY"; fi
IFS=" "

debconf-apt-progress -- apt-get -y install linux-image$ROOT_BRACH-$LINUXFAMILY
debconf-apt-progress -- apt-get -y install linux-firmware-image$ROOT_BRACH-$LINUXFAMILY linux-u-boot-$BOARD linux-headers$ROOT_BRACH-$LINUXFAMILY
debconf-apt-progress -- apt-get -y install linux-$(lsb_release -cs)-root$ROOT_BRACH-$BOARD $PACKETS
}
#--------------------------------------------------------------------------------------------------------------------------------



#--------------------------------------------------------------------------------------------------------------------------------
# Program start
#--------------------------------------------------------------------------------------------------------------------------------

display_warning
install_packets_and_repo
get_hardware_info
mount_boot_device
create_boot_script
select_boards
remove_old
install_new

apt-get -y upgrade

echo ""
echo "All done. Check boot scripts and reboot for changes to take effect!"
echo ""

if [[ "$bootdevice" == "/dev/nand1" ]]; then
	cp /boot/bin/$BOARD /mnt/script.bin
	whiptail --title "NAND install" --infobox "Converting and copying kernel." 7 60
    sed -e 's,script=.*,script=script.bin,g' -i /mnt/uEnv.txt 	
	mkimage -A arm -O linux -T kernel -C none -a "0x40008000" -e "0x40008000" -n "Linux kernel" -d /boot/zImage /mnt/uImage
elif [[ "$rootdevice" == "/dev/mmcblk0p2" ]]; then
	# fat boot, two partitions
	cp /boot/bin/$BOARD.bin /boot/script.bin
else
   ln -sf /boot/bin/$BOARD.bin /boot/script.bin
fi

echo "Visit: forum.armbian.com in case of troubles or just for fun ;)"
echo ""