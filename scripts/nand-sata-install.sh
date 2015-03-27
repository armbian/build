#!/bin/bash
#
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
#
# www.igorpecovnik.com / images + support
#
# NAND, SATA and USB ARM rootfs install
#
# Should work with: Cubietruck, Cubieboards, BananaPi, Olimex Lime+Lime2+Micro, Hummingboard, ...
#


#--------------------------------------------------------------------------------------------------------------------------------
# this is file is needed to conduct 2nd stage install for NAND installation
#--------------------------------------------------------------------------------------------------------------------------------
FLAG=".reboot-nand-install.pid"


#--------------------------------------------------------------------------------------------------------------------------------
# we don't need to copy all files. This is the exclusion list
#--------------------------------------------------------------------------------------------------------------------------------
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


#--------------------------------------------------------------------------------------------------------------------------------
# Let's see where we are running from ?
#--------------------------------------------------------------------------------------------------------------------------------
SOURCE=$(dmesg |grep root)
SOURCE=${SOURCE#"${SOURCE%%root=*}"}
SOURCE=`echo $SOURCE| cut -d' ' -f 1`
SOURCE="${SOURCE//root=/}"


#--------------------------------------------------------------------------------------------------------------------------------
# Which kernel and bin do we run
#--------------------------------------------------------------------------------------------------------------------------------
KERNEL=$(ls -l /boot/ |grep vmlinuz |awk '{print $NF}')
BINFILE=$(cat /boot/boot.cmd |grep .bin |awk '{print $NF}')


#--------------------------------------------------------------------------------------------------------------------------------
# How much space do we use?
#--------------------------------------------------------------------------------------------------------------------------------
USAGE=$(df -BM | grep ^/dev | head -1 | awk '{print $3}')
USAGE=${USAGE%?}


#--------------------------------------------------------------------------------------------------------------------------------
# What are our possible destinations?
#--------------------------------------------------------------------------------------------------------------------------------
# NAND
if [[ $KERNEL == *"3.4"*  ]]; then
	# There is no NAND support in mainline yet
	if [ "$(grep nand /proc/partitions)" != "" ]; then
        # We have nand, check size
        NAND_SIZE=$(awk 'BEGIN { printf "%.0f\n", '$(grep nand /proc/partitions | awk '{print $3}' | head -1)'/1024 }')
        NAND_ROOT_PART=/dev/nand2
	fi
fi
# SATA
if [ "$(grep sda /proc/partitions)" != "" ]; then
        # We have something as sd, check size
        SDA_SIZE=$(awk 'BEGIN { printf "%.0f\n", '$(grep sda /proc/partitions | awk '{print $3}' | head -1)'/1024 }')
        # Check which type is this drive - SATA or USB
        SDA_TYPE=$(udevadm info --query=all --name=sda | grep ID_BUS=)
        SDA_TYPE=${SDA_TYPE#*=}
        SDA_NAME=$(udevadm info --query=all --name=sda | grep ID_MODEL=)
        SDA_NAME=${SDA_NAME#*=}
        SDA_ROOT_PART=/dev/sda1
fi


#--------------------------------------------------------------------------------------------------------------------------------
# NAND install
#--------------------------------------------------------------------------------------------------------------------------------
if [ -f $FLAG ]; then
	clear
	whiptail --title "NAND install" --infobox "Formatting and optimizing NAND rootfs ... up to 30 sec." 7 60
	mkfs.vfat /dev/nand1 > /dev/null 2>&1
	mkfs.ext4 /dev/nand2 > /dev/null 2>&1
	mount /dev/nand1 /mnt
	whiptail --title "NAND install" --infobox "Creating NAND bootfs ... few seconds." 7 60
	tar xfz nand1-allwinner.tgz -C /mnt/
	cp $BINFILE /mnt/script.bin
	whiptail --title "NAND install" --infobox "Converting and copying kernel." 7 60
	mkimage -A arm -O linux -T kernel -C none -a "0x40008000" -e "0x40008000" -n "Linux kernel" -d /boot/$KERNEL /mnt/uImage > /dev/null 2>&1
	umount /mnt
	mount /dev/nand2 /mnt
	whiptail --title "NAND install" --infobox "Checking and counting files." 7 60
	TODO=$(rsync -avrltD --delete --stats --human-readable --dry-run --exclude-from=.install-exclude  /  /mnt |grep "^Number of files:"|awk '{print $4}')
	TODO="${TODO//./}"
	TODO="${TODO//,/}"
	whiptail --title "NAND install" --infobox "Copy / creating rootfs on NAND: $TODO files." 7 60
	rsync -avrltD --delete --stats --human-readable --exclude-from=.install-exclude  /  /mnt | pv -l -e -p -s $TODO >/dev/null
	me=`basename $0`
	# copy this script and my README to NAND that you can coduct NAND / SATA install if you want
	cp readme.txt $me /mnt/root
	# change fstab - mount NAND boot partition
	sed -e 's/mmcblk0p1/nand2/g' -i /mnt/etc/fstab
	echo "/dev/nand1	/boot	vfat	defaults	0	0" >> /mnt/etc/fstab
	umount /mnt
	whiptail --title "NAND install" --infobox "All done. Press a key to power off, then remove SD to boot from NAND." 9 60
	rm $FLAG .install-exclude
	read konec
	poweroff
	exit
fi


#--------------------------------------------------------------------------------------------------------------------------------
# Prepare main selection
#--------------------------------------------------------------------------------------------------------------------------------
TEXT="\nSource:\n"
TEXT=$TEXT"\nRoot file-system:     $SOURCE"
TEXT=$TEXT"\nKernel file:          $KERNEL"
TEXT=$TEXT"\nBoard configuration:  $BINFILE"
TEXT=$TEXT"\nUsed space:           $USAGE MB"
TEXT=$TEXT"\n\nDestination:\n"

# if we have nand
if [ "$NAND_ROOT_PART" != "" ]; then LIST=$LIST"%$NAND_ROOT_PART%($NAND_SIZE MB) internal flash"; fi
# if we have sda
if [ "$SDA_ROOT_PART" != "" ]; then LIST=$LIST"%$SDA_ROOT_PART%($SDA_SIZE MB) $SDA_TYPE drive $SDA_NAME"; fi
# exit if none avaliable
if [ "$LIST" == "" ]; then echo "No targets avaliable!"; exit; fi

# Some text
LIST=${LIST:1}
BACKTITLE="(c) Igor Pecovnik"
MENUTITLE="\n$TEXT\nWhere do you want to have root-filesystem?"


IFS="%"
DEST=$(whiptail --title "ARM boards installer" --backtitle $BACKTITLE --menu $MENUTITLE 22 60 2 --cancel-button Cancel --ok-button Select $LIST 3>&1 1>&2 2>&3) 
DESTPART="${DEST///dev\//}"

# exit if none avaliable
if [ "$DEST" == "" ]; then echo "No targets choosen!"; exit; fi

# exit if target not partitioned
if [[ -z $(cat /proc/partitions | grep $DESTPART) ]]; then 
        echo "Device $DEST not partitioned";
        exit 0
fi

# show big warning
toilet -f mono12 WARNING > test_textbox
echo "\nThis script will erase your device ($DEST) and copy content of SD card to it!\n\nPress OK to continue, CTRL C to cancel." >> test_textbox
whiptail --textbox test_textbox 20 74 

#--------------------------------------------------------------------------------------------------------------------------------
# NAND install first part - partitioning
#--------------------------------------------------------------------------------------------------------------------------------
if [[ $DESTPART == *nand*  ]]; then
	clear
	echo "Partitioning"
	(echo y;) | nand-part -f a20 /dev/nand 32768 'bootloader 32768' 'rootfs 0' >> /dev/null || true
	whiptail --title "Reboot required" --msgbox "Press OK to reboot than run this script again!" 7 60
	touch $FLAG
	reboot
fi

#--------------------------------------------------------------------------------------------------------------------------------
# SATA install can be done in one step
#--------------------------------------------------------------------------------------------------------------------------------
if [[ $DESTPART == *sda*  ]]; then
	clear
	whiptail --title "SATA & USB install" --infobox "Formatting and optimizing $SDA_TYPE rootfs ..." 7 60
	mkfs.ext4 /dev/sda1 > /dev/null 2>&1
	mount /dev/sda1 /mnt
	sync
	sleep 2
	whiptail --title "$SDA_TYPE install" --infobox "Checking and counting files." 7 60
	TODO=$(rsync -avrltD --delete --stats --human-readable --dry-run --exclude-from=.install-exclude  /  /mnt |grep "^Number of files:"|awk '{print $4}')
	TODO="${TODO//./}"
	TODO="${TODO//,/}"
	whiptail --title "$SDA_TYPE install" --infobox "Copy / creating rootfs on $SDA_TYPE: $TODO files." 7 60
	rsync -avrltD --delete --stats --human-readable --exclude-from=.install-exclude  /  /mnt | pv -l -e -p -s "$TODO" >/dev/null
	if [[ $SOURCE == *nand*  ]]; then
		sed -e 's,nand_root=\/dev\/nand2,nand_root=/dev/'"$DESTPART"',g' -i /boot/uEnv.txt
		# change fstab
		sed -e 's/nand2/sda1/g' -i /mnt/etc/fstab
	else

		if [[ $KERNEL == *"3.4"*  ]]; then
		sed -e 's,root=\/dev\/mmcblk0p1,root=/dev/'"$DESTPART"',g' -i /boot/boot.cmd
		mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
		else
		sed -e 's,root=\/dev\/mmcblk0p1,root=/dev/'"$DESTPART"',g' -i /boot/uEnv.txt
		sed -e 's,root=\/dev\/mmcblk0p1,root=/dev/'"$DESTPART"',g' -i /boot/boot-next.cmd
                if [ -f /boot/boot-next.cmd ]; then
                        mkimage -C none -A arm -T script -d /boot/boot-next.cmd /boot/boot.scr
                fi
		fi
		# change fstab
		sed -e 's/mmcblk0p1/sda1/g' -i /mnt/etc/fstab
		sed -i "s/data=writeback,//" /mnt/etc/fstab
		mkdir -p /mnt/media/mmc
		echo "/dev/mmcblk0p1        /media/mmc   ext4    defaults        0       0" >> /mnt/etc/fstab
		echo "/media/mmc/boot   /boot   none    bind        0       0" >> /mnt/etc/fstab
	fi
whiptail --title "Reboot required" --msgbox "Press OK to reboot!" 7 60
reboot
fi