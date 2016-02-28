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
#
# Functions:
# custom_debootstrap
# shrinking_raw_image
# closing_image
# install_packet

custom_debootstrap (){
#---------------------------------------------------------------------------------------------------------------------------------
# Create clean and fresh Debian and Ubuntu image template if it does not exists
#---------------------------------------------------------------------------------------------------------------------------------

# is boot partition to big?
#if [ "$SDSIZE" -le "$(($OFFSET+$BOOTSIZE))" ]; then
#	display_alert "Image size too small." "$BOOTSIZE > $SDSIZE" "err"
#	exit
#fi

# create needed directories and mount image to next free loop device
rm -rf $DEST/cache/sdcard/
mkdir -p $DEST/cache/rootfs $DEST/cache/sdcard

cd $DEST/cache

# We need to re-calculate from human to machine 
BOOTSTART=$(($OFFSET*2048))
ROOTSTART=$(($BOOTSTART+($BOOTSIZE*2048)))
BOOTEND=$(($ROOTSTART-1))

# Create image file

if [ "$OUTPUT_DIALOG" = "yes" ]; then
	(dd if=/dev/zero bs=1M status=none count=$SDSIZE | pv -n -s $(( $SDSIZE * 1024 * 1024 )) | dd status=none of=$DEST/cache/tmprootfs.raw) 2>&1 \
	| dialog --backtitle "$backtitle" --title "Creating blank image ($SDSIZE), please wait ..." --gauge "" 5 70
else
	dd if=/dev/zero bs=1M status=none count=$SDSIZE | pv -p -b -r -s $(( $SDSIZE * 1024 * 1024 )) | dd status=none of=$DEST/cache/tmprootfs.raw
fi

# Find first available free device
LOOP=$(losetup -f)

if [[ "$LOOP" != "/dev/loop0" && "$LOOP" != "/dev/loop1" ]]; then
display_alert "You run out of loop devices" "pleese reboot" "error"
exit
fi

# Mount image as block device
losetup $LOOP $DEST/cache/tmprootfs.raw
sync

# Create partitions and file-system
parted -s $LOOP -- mklabel msdos
if [ "$BOOTSIZE" -eq "0" ]; then 
	parted -s $LOOP -- mkpart primary ext4  $ROOTSTART"s" -1s
	partprobe $LOOP
	mkfs.ext4 -q $LOOP"p1"
	mount $LOOP"p1" $DEST/cache/sdcard/
else
	parted -s $LOOP -- mkpart primary fat16  $BOOTSTART"s" $BOOTEND"s"
	parted -s $LOOP -- mkpart primary ext4  $ROOTSTART"s" -1s
	partprobe $LOOP
	mkfs.vfat -n "$IMAGEVOLUME" $LOOP"p1" >/dev/null 2>&1
	mkfs.ext4 -q $LOOP"p2"
	mount $LOOP"p2" $DEST/cache/sdcard/
	mkdir -p $DEST/cache/sdcard/boot
	mount $LOOP"p1" $DEST/cache/sdcard/boot
fi

# rootfs cache file name
[[ $BUILD_DESKTOP == yes ]] && local variant_desktop=yes
local packages_hash=$(md5sum <<< $PACKAGE_LIST | cut -d' ' -f 1)
local cache_fname="$DEST/cache/rootfs/$RELEASE${variant_desktop:+_desktop}.$packages_hash.tgz"

# Uncompress from cache
if [ -f "$cache_fname" ]; then
	filemtime=`stat -c %Y $cache_fname`
	currtime=`date +%s`
	diff=$(( (currtime - filemtime) / 86400 ))
	display_alert "Extracting $RELEASE from cache" "$diff days old" "info"
	pv -p -b -r -c -N "$(basename $cache_fname)" "$cache_fname" | pigz -dc | tar xp -C $DEST/cache/sdcard/
	rm $DEST/cache/sdcard/etc/resolv.conf
	echo "nameserver 8.8.8.8" > $DEST/cache/sdcard/etc/resolv.conf
	if [ "$diff" -gt "3" ]; then
		chroot $DEST/cache/sdcard /bin/bash -c "apt-get update" | dialog --backtitle "$backtitle" --title "Force package update ..." --progressbox 20 70
	fi
fi

# If we don't have a filesystem cached, let's make em
if [ ! -f "$cache_fname" ]; then

# debootstrap base system
[[ $DISTRIBUTION == "Debian" ]] && local redir="http://httpredir.debian.org/debian/"
debootstrap --include=openssh-server,debconf-utils --arch=armhf --foreign $RELEASE $DEST/cache/sdcard/ $redir | dialog --backtitle "$backtitle" --title "Debootstrap $DISTRIBUTION $RELEASE base system to image template ..." --progressbox 20 70

# we need emulator for second stage
cp /usr/bin/qemu-arm-static $DEST/cache/sdcard/usr/bin/

# and keys
d=$DEST/cache/sdcard/usr/share/keyrings/
test -d "$d" || mkdir -p "$d" && cp /usr/share/keyrings/debian-archive-keyring.gpg "$d" 

# enable arm binary format so that the cross-architecture chroot environment will work
test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm

# debootstrap second stage
chroot $DEST/cache/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage" | dialog --backtitle "$backtitle" --title "Installing $DISTRIBUTION $RELEASE base system to image template ..." --progressbox 20 70

# mount proc, sys and dev
mount -t proc chproc $DEST/cache/sdcard/proc
mount -t sysfs chsys $DEST/cache/sdcard/sys
mount -t devtmpfs chdev $DEST/cache/sdcard/dev || mount --bind /dev $DEST/cache/sdcard/dev
mount -t devpts chpts $DEST/cache/sdcard/dev/pts

# choose proper apt list
cp $SRC/lib/config/sources.list.$RELEASE $DEST/cache/sdcard/etc/apt/sources.list

# add armbian key
echo "deb http://apt.armbian.com $RELEASE main" > $DEST/cache/sdcard/etc/apt/sources.list.d/armbian.list
cp $SRC/lib/bin/armbian.key $DEST/cache/sdcard 
chroot $DEST/cache/sdcard /bin/bash -c "cat armbian.key | apt-key add -"
rm $DEST/cache/sdcard/armbian.key

# update and upgrade
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y update" | dialog --progressbox "Updating package databases ..." 20 70

# generate locales and install packets
display_alert "Install locales" "$DEST_LANG" "info"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y -qq install locales"
if [ -f $DEST/cache/sdcard/etc/locale.gen ]; then sed -i "s/^# $DEST_LANG/$DEST_LANG/" $DEST/cache/sdcard/etc/locale.gen; fi
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "locale-gen $DEST_LANG"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "export CHARMAP=$CONSOLE_CHAR FONTFACE=8x16 LANG=$DEST_LANG LANGUAGE=$DEST_LANG DEBIAN_FRONTEND=noninteractive"
LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"

install_packet "$PACKAGE_LIST" "Installing Armbian on the top of $DISTRIBUTION $RELEASE base system ..."

chroot $DEST/cache/sdcard /bin/bash -c "apt-get clean"
chroot $DEST/cache/sdcard /bin/bash -c "sync"
chroot $DEST/cache/sdcard /bin/bash -c "unset DEBIAN_FRONTEND"
sync
sleep 3
# unmount proc, sys and dev from chroot
umount -l $DEST/cache/sdcard/dev/pts
umount -l $DEST/cache/sdcard/dev
umount -l $DEST/cache/sdcard/proc
umount -l $DEST/cache/sdcard/sys

# kill process inside
KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  
KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  

display_alert "Closing debootstrap process and preparing cache." "" "info"
tar cp --directory=$DEST/cache/sdcard/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
--exclude='./mnt/*' --exclude='./sys/*' . | pv -p -b -r -s $(du -sb $DEST/cache/sdcard/ | cut -f1) -N "$(basename $cache_fname)" | pigz > $cache_fname
fi
#
# mount proc, sys and dev
mount -t proc chproc $DEST/cache/sdcard/proc
mount -t sysfs chsys $DEST/cache/sdcard/sys
mount -t devtmpfs chdev $DEST/cache/sdcard/dev || mount --bind /dev $DEST/cache/sdcard/dev
mount -t devpts chpts $DEST/cache/sdcard/dev/pts
}

shrinking_raw_image (){ # Parameter: RAW image with full path
#---------------------------------------------------------------------------------------------------------------------------------
# Shrink partition and image to real size with a place for 128Mb swap space
#---------------------------------------------------------------------------------------------------------------------------------
RAWIMAGE=$1
display_alert "Shrink image last partition to" "minimum" "info"

# partition prepare
LOOP=$(losetup -f)
losetup $LOOP $RAWIMAGE
PARTSTART=$(parted $LOOP unit s print -sm | tail -1 | cut -d: -f2 | sed 's/s//')
PARTEND=$(parted $LOOP unit s print -sm | head -3 | tail -1 | cut -d: -f3 | sed 's/s//') # end of first partition
PARTSTARTBLOCKS=$(($PARTSTART*512))
echo "PARTSTART $PARTSTART PARTEND $PARTEND PARTSTARTBLOCKS $PARTSTARTBLOCKS" >> $DEST/debug/install.log 
sleep 1; losetup -d $LOOP

# convert from EXT4 to EXT2
sleep 1; losetup -o $PARTSTARTBLOCKS $LOOP $RAWIMAGE
sleep 1; fsck -n $LOOP >/dev/null 2>&1
sleep 1; tune2fs -O ^has_journal $LOOP >/dev/null 2>&1
sleep 1; e2fsck -fy $LOOP >/dev/null 2>&1
resize2fs $LOOP -M >/dev/null 2>&1
BLOCKSIZE=$(LANGUAGE=english tune2fs -l $LOOP | grep "Block count" | awk '{ print $(NF)}')
RESERVEDBLOCKSIZE=$(LANGUAGE=english tune2fs -l $LOOP | grep "Reserved block count" | awk '{ print $(NF)}')
BLOCKSIZE=$(($PARTSTART+$BLOCKSIZE+50000)) # fixed reserve to be enough for swap file creation
echo "BLOCKSIZE $BLOCKSIZE RESERVEDBLOCKSIZE $RESERVEDBLOCKSIZE" >> $DEST/debug/install.log 
resize2fs $LOOP $BLOCKSIZE >/dev/null 2>&1
tune2fs -O has_journal $LOOP >/dev/null 2>&1
tune2fs -o journal_data_writeback $LOOP >/dev/null 2>&1
losetup -d $LOOP

# mount once again and create new partition
sleep 1; losetup $LOOP $RAWIMAGE
PARTITIONS=$(parted -m $LOOP 'print' | tail -1 | awk -F':' '{ print $1 }')

parted $LOOP rm $PARTITIONS >/dev/null 2>&1
NEWSIZE=$((($BLOCKSIZE)*4096/1024))

STARTFROM=$(($PARTEND+1)) # if we have two partitions, start of second one is where first one ends +1
[[ $PARTITIONS == 1 ]] && STARTFROM=$PARTSTART

((echo n; echo p; echo ; echo $STARTFROM; echo "+"$NEWSIZE"K"; echo w;) | fdisk $LOOP)>/dev/null
sleep 1

# truncate the image
TRUNCATE=$(parted -m $LOOP 'unit s print' | tail -1 | awk -F':' '{ print $3 }' | sed 's/.$//')
TRUNCATE=$((($TRUNCATE+1)*512))
truncate -s $TRUNCATE $RAWIMAGE >/dev/null 2>&1
losetup -d $LOOP
echo "NEWSIZE $NEWSIZE STARTFROM $STARTFROM TRUNCATE $TRUNCATE" >> $DEST/debug/install.log 
}


closing_image (){
#--------------------------------------------------------------------------------------------------------------------------------
# Closing image and clean-up 									            
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Possible after install." "customize-image.sh" "info"
cp $SRC/userpatches/customize-image.sh $DEST/cache/sdcard/tmp/customize-image.sh
chmod +x $DEST/cache/sdcard/tmp/customize-image.sh
chroot $DEST/cache/sdcard /bin/bash -c "/tmp/customize-image.sh $RELEASE $FAMILY $BOARD $BUILD_DESKTOP"
chroot $DEST/cache/sdcard /bin/bash -c "sync"
sync
sleep 3
# unmount proc, sys and dev from chroot
umount -l $DEST/cache/sdcard/dev/pts
umount -l $DEST/cache/sdcard/dev
umount -l $DEST/cache/sdcard/proc
umount -l $DEST/cache/sdcard/sys
umount -l $DEST/cache/sdcard/tmp >/dev/null 2>&1

# let's create nice file name
VER="${VER/-$LINUXFAMILY/}"
VERSION=$VERSION" "$VER
VERSION="${VERSION// /_}"
VERSION="${VERSION//$BRANCH/}"
VERSION="${VERSION//__/_}"

if [ "$BUILD_DESKTOP" = "yes" ]; then
VERSION=$VERSION"_desktop"
fi
 

# kill process inside
KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  
KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi  

# same info outside the image
cp $DEST/cache/sdcard/etc/armbian.txt $DEST/cache/
sleep 2
rm $DEST/cache/sdcard/usr/bin/qemu-arm-static 
sleep 2
umount -l $DEST/cache/sdcard/boot > /dev/null 2>&1 || /bin/true
umount -l $DEST/cache/sdcard/ 
sleep 2
losetup -d $LOOP
rm -rf $DEST/cache/sdcard/

# write bootloader
LOOP=$(losetup -f)
losetup $LOOP $DEST/cache/tmprootfs.raw
write_uboot $LOOP
sleep 3
losetup -d $LOOP
sync
sleep 2
mv $DEST/cache/tmprootfs.raw $DEST/cache/$VERSION.raw
sync
sleep 2
# let's shrint it
shrinking_raw_image "$DEST/cache/$VERSION.raw" "15"
sleep 2
cd $DEST/cache/
cp $SRC/lib/bin/imagewriter.exe .
# sign with PGP
if [[ $GPG_PASS != "" ]] ; then
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes $VERSION.raw	
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes imagewriter.exe
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes armbian.txt
fi
display_alert "Create and sign" "$VERSION.zip" "info"
mkdir -p $DEST/images
if [[ $COMPRESS_OUTPUTIMAGE == no ]]; then
	rm -f *.asc imagewriter.* armbian.txt
	mv *.raw $DEST/images/
else
	zip -FSq $DEST/images/$VERSION.zip $VERSION.raw* armbian.txt imagewriter.*	
	rm -f $VERSION.raw *.asc imagewriter.* armbian.txt	
fi
}

install_packet ()
{
#--------------------------------------------------------------------------------------------------------------------------------
# Install packets inside chroot
#--------------------------------------------------------------------------------------------------------------------------------
i=0
j=1
declare -a PACKETS=($1)
skupaj=${#PACKETS[@]}
while [[ $i -lt $skupaj ]]; do
procent=$(echo "scale=2;($j/$skupaj)*100"|bc)
procent=${procent%.*}
		x=${PACKETS[$i]}
		if [[ $3 == "host" ]]; then
			DEBIAN_FRONTEND=noninteractive apt-get -qq -y install $x >> $DEST/debug/install.log  2>&1
		else
			chroot $DEST/cache/sdcard /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -qq -y install $x" >> $DEST/debug/install.log 2>&1
		fi
		
		if [ $? -ne 0 ]; then display_alert "Installation of package failed" "$INSTALL" "err"; exit 1; fi
		
		if [[ $4 != "quiet" ]]; then
			printf '%.0f\n' $procent | dialog --backtitle "$backtitle" --title "$2" --gauge "\n\n$x" 9 70
		fi
		i=$[$i+1]
		j=$[$j+1]
done
}
