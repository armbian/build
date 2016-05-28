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
# umount_image

custom_debootstrap (){
#---------------------------------------------------------------------------------------------------------------------------------
# Create clean and fresh Debian and Ubuntu image template if it does not exists
#---------------------------------------------------------------------------------------------------------------------------------

# needed if process failed in the middle
umount_image

# create needed directories and mount image to next free loop device
rm -rf $CACHEDIR/sdcard/
mkdir -p $CACHEDIR/rootfs $CACHEDIR/sdcard

cd $CACHEDIR

# We need to re-calculate from human to machine
BOOTSTART=$(($OFFSET*2048))
ROOTSTART=$(($BOOTSTART+($BOOTSIZE*2048)))
BOOTEND=$(($ROOTSTART-1))

# Create image file

if [ "$OUTPUT_DIALOG" = "yes" ]; then
	(dd if=/dev/zero bs=1M status=none count=$SDSIZE | pv -n -s $(( $SDSIZE * 1024 * 1024 )) | dd status=none of=$CACHEDIR/tmprootfs.raw) 2>&1 \
	| dialog --backtitle "$backtitle" --title "Creating blank image ($SDSIZE), please wait ..." --gauge "" 5 70
else
	dd if=/dev/zero bs=1M status=none count=$SDSIZE | pv -p -b -r -s $(( $SDSIZE * 1024 * 1024 )) | dd status=none of=$CACHEDIR/tmprootfs.raw
fi

# Find first available free device
LOOP=$(losetup -f)

if [[ "$LOOP" != "/dev/loop0" && "$LOOP" != "/dev/loop1" ]]; then
display_alert "You run out of loop devices" "pleese reboot" "error"
exit
fi

# Mount image as block device
losetup $LOOP $CACHEDIR/tmprootfs.raw
sync

# Create partitions and file-system
parted -s $LOOP -- mklabel msdos
if [ "$BOOTSIZE" -eq "0" ]; then
	parted -s $LOOP -- mkpart primary ext4  $ROOTSTART"s" -1s
	partprobe $LOOP
	
	# older mkfs.ext4 desn't know about 64bit and metadata_csum options
	local codename=$(lsb_release -sc)
	if [[ "$codename" == "sid" ]]; then
		mkfs.ext4 -O ^64bit,^metadata_csum,uninit_bg -q $LOOP"p1"		
	else
		mkfs.ext4 -q $LOOP"p1"
	fi
	
	mount $LOOP"p1" $CACHEDIR/sdcard/
else
	parted -s $LOOP -- mkpart primary fat16  $BOOTSTART"s" $BOOTEND"s"
	parted -s $LOOP -- mkpart primary ext4  $ROOTSTART"s" -1s
	partprobe $LOOP
	mkfs.vfat -n "$IMAGEVOLUME" $LOOP"p1" >/dev/null 2>&1
	mkfs.ext4 -q $LOOP"p2"
	mount $LOOP"p2" $CACHEDIR/sdcard/
	mkdir -p $CACHEDIR/sdcard/boot
	mount $LOOP"p1" $CACHEDIR/sdcard/boot
fi

# rootfs cache file name
[[ $BUILD_DESKTOP == yes ]] && local variant_desktop=yes
local packages_hash=$(get_package_list_hash $PACKAGE_LIST)
local cache_fname="$CACHEDIR/rootfs/$RELEASE${variant_desktop:+_desktop}-$ARCH.$packages_hash.tgz"

# Uncompress from cache
if [ -f "$cache_fname" ]; then
	filemtime=`stat -c %Y $cache_fname`
	currtime=`date +%s`
	diff=$(( (currtime - filemtime) / 86400 ))
	display_alert "Extracting $RELEASE from cache" "$diff days old" "info"
	pv -p -b -r -c -N "$(basename $cache_fname)" "$cache_fname" | pigz -dc | tar xp -C $CACHEDIR/sdcard/
	rm $CACHEDIR/sdcard/etc/resolv.conf
	echo "nameserver 8.8.8.8" > $CACHEDIR/sdcard/etc/resolv.conf
	if [ "$diff" -gt "3" ]; then
		chroot $CACHEDIR/sdcard /bin/bash -c "apt-get update" | dialog --backtitle "$backtitle" --title "Force package update ..." --progressbox $TTY_Y $TTY_X
	fi
fi

# If we don't have a filesystem cached, let's make em
if [ ! -f "$cache_fname" ]; then

# debootstrap base system
[[ -n $PACKAGE_LIST_EXCLUDE ]] && local package_exclude="--exclude="${PACKAGE_LIST_EXCLUDE// /,}
[[ $DISTRIBUTION == "Debian" ]] && local redir="http://httpredir.debian.org/debian/"
debootstrap --include=openssh-server $package_exclude --arch=$ARCH --foreign $RELEASE $CACHEDIR/sdcard/ $redir | dialog --backtitle "$backtitle" --title "Debootstrap $DISTRIBUTION $RELEASE base system to image template ..." --progressbox $TTY_Y $TTY_X

# we need emulator for second stage
cp /usr/bin/$QEMU_BINARY $CACHEDIR/sdcard/usr/bin/

# and keys
d=$CACHEDIR/sdcard/usr/share/keyrings/
test -d "$d" || mkdir -p "$d" && cp /usr/share/keyrings/debian-archive-keyring.gpg "$d"

# enable arm binary format so that the cross-architecture chroot environment will work
test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm

# debootstrap second stage
chroot $CACHEDIR/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage" | dialog --backtitle "$backtitle" --title "Installing $DISTRIBUTION $RELEASE base system to image template ..." --progressbox $TTY_Y $TTY_X

# mount proc, sys and dev
mount -t proc chproc $CACHEDIR/sdcard/proc
mount -t sysfs chsys $CACHEDIR/sdcard/sys
mount -t devtmpfs chdev $CACHEDIR/sdcard/dev || mount --bind /dev $CACHEDIR/sdcard/dev
mount -t devpts chpts $CACHEDIR/sdcard/dev/pts

# choose proper apt list
cp $SRC/lib/config/apt/sources.list.$RELEASE $CACHEDIR/sdcard/etc/apt/sources.list

# add armbian key
echo "deb http://apt.armbian.com $RELEASE main" > $CACHEDIR/sdcard/etc/apt/sources.list.d/armbian.list
cp $SRC/lib/bin/armbian.key $CACHEDIR/sdcard
chroot $CACHEDIR/sdcard /bin/bash -c "cat armbian.key | apt-key add -"
rm $CACHEDIR/sdcard/armbian.key

# update and upgrade
LC_ALL=C LANGUAGE=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "apt-get -y update" | dialog --progressbox "Updating package databases ..." $TTY_Y $TTY_X

# generate locales and install packets
display_alert "Install locales" "$DEST_LANG" "info"
LC_ALL=C LANGUAGE=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "apt-get -y -qq install locales"
if [ -f $CACHEDIR/sdcard/etc/locale.gen ]; then sed -i "s/^# $DEST_LANG/$DEST_LANG/" $CACHEDIR/sdcard/etc/locale.gen; fi
LC_ALL=C LANGUAGE=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "locale-gen $DEST_LANG"
LC_ALL=C LANGUAGE=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "export CHARMAP=$CONSOLE_CHAR FONTFACE=8x16 LANG=$DEST_LANG LANGUAGE=$DEST_LANG DEBIAN_FRONTEND=noninteractive"
LC_ALL=C LANGUAGE=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"

install_packet "$PACKAGE_LIST" "Installing Armbian on the top of $DISTRIBUTION $RELEASE base system ..."

chroot $CACHEDIR/sdcard /bin/bash -c "apt-get clean"
chroot $CACHEDIR/sdcard /bin/bash -c "sync"
chroot $CACHEDIR/sdcard /bin/bash -c "unset DEBIAN_FRONTEND"
sync
sleep 3
# unmount proc, sys and dev from chroot
umount -l $CACHEDIR/sdcard/dev/pts
umount -l $CACHEDIR/sdcard/dev
umount -l $CACHEDIR/sdcard/proc
umount -l $CACHEDIR/sdcard/sys

# kill process inside
KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi
KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi
KILLPROC=$(ps -uax | pgrep bluetoothd | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi
KILLPROC=$(ps -uax | pgrep acpid | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi
KILLPROC=$(ps -uax | pgrep python | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi

display_alert "Closing debootstrap process and preparing cache." "" "info"
tar cp --directory=$CACHEDIR/sdcard/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
--exclude='./mnt/*' --exclude='./sys/*' . | pv -p -b -r -s $(du -sb $CACHEDIR/sdcard/ | cut -f1) -N "$(basename $cache_fname)" | pigz > $cache_fname
fi
#
# mount proc, sys and dev
mount -t proc chproc $CACHEDIR/sdcard/proc
mount -t sysfs chsys $CACHEDIR/sdcard/sys
mount -t devtmpfs chdev $CACHEDIR/sdcard/dev || mount --bind /dev $CACHEDIR/sdcard/dev
mount -t devpts chpts $CACHEDIR/sdcard/dev/pts
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
customize_image
chroot $CACHEDIR/sdcard /bin/bash -c "sync"
sync
sleep 3
# unmount proc, sys and dev from chroot
umount -l $CACHEDIR/sdcard/dev/pts
umount -l $CACHEDIR/sdcard/dev
umount -l $CACHEDIR/sdcard/proc
umount -l $CACHEDIR/sdcard/sys
umount -l $CACHEDIR/sdcard/tmp >/dev/null 2>&1

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
KILLPROC=$(ps -uax | pgrep bluetoothd | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi
KILLPROC=$(ps -uax | pgrep acpid | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi

# same info outside the image
cp $CACHEDIR/sdcard/etc/armbian.txt $CACHEDIR/
sleep 2
rm -f $CACHEDIR/sdcard/usr/bin/$QEMU_BINARY
sleep 2
umount -l $CACHEDIR/sdcard/boot > /dev/null 2>&1 || /bin/true
umount -l $CACHEDIR/sdcard/
sleep 2
losetup -d $LOOP
rm -rf $CACHEDIR/sdcard/

# write bootloader
LOOP=$(losetup -f)
losetup $LOOP $CACHEDIR/tmprootfs.raw
write_uboot $LOOP
sleep 3
losetup -d $LOOP
sync
sleep 2
mv $CACHEDIR/tmprootfs.raw $CACHEDIR/$VERSION.raw
sync
sleep 2
# let's shrint it
shrinking_raw_image "$CACHEDIR/$VERSION.raw" "15"
sleep 2
cd $CACHEDIR/
cp $SRC/lib/bin/imagewriter.exe .
# sign with PGP
if [[ $GPG_PASS != "" ]] ; then
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes $VERSION.raw
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes imagewriter.exe
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes armbian.txt
fi
display_alert "Signing and compressing" "Please wait!" "info"
mkdir -p $DEST/images
if [[ $COMPRESS_OUTPUTIMAGE != yes ]]; then
	rm -f *.asc imagewriter.* armbian.txt
	mv *.raw $DEST/images/
else
	if [[ $SEVENZIP == yes ]]; then
		FILENAME=$DEST/images/$VERSION.7z
		7za a -t7z -bd -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on $FILENAME $VERSION.raw* armbian.txt imagewriter.* >/dev/null 2>&1
	else
		FILENAME=$DEST/images/$VERSION.zip
		zip -FSq $FILENAME $VERSION.raw* armbian.txt imagewriter.*
	fi
	rm -f $VERSION.raw *.asc armbian.txt
	FILESIZE=$(ls -l --b=M $FILENAME | cut -d " " -f5)
	display_alert "Done building" "$FILENAME [$FILESIZE]" "info"
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
	chroot $CACHEDIR/sdcard /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -qq -y install $x --no-install-recommends" >> $DEST/debug/install.log 2>&1
	if [ $? -ne 0 ]; then display_alert "Installation of package failed" "$INSTALL" "err"; exit 1; fi
	printf '%.0f\n' $procent | dialog --backtitle "$backtitle" --title "$2" --gauge "\n\n$x" 9 70
	i=$[$i+1]
	j=$[$j+1]
done
}

umount_image (){
umount -l $CACHEDIR/sdcard/dev/pts >/dev/null 2>&1
umount -l $CACHEDIR/sdcard/dev >/dev/null 2>&1
umount -l $CACHEDIR/sdcard/proc >/dev/null 2>&1
umount -l $CACHEDIR/sdcard/sys >/dev/null 2>&1
umount -l $CACHEDIR/sdcard/tmp >/dev/null 2>&1
umount -l $CACHEDIR/sdcard >/dev/null 2>&1
x=$(losetup -a | awk '{ print $1 }' | rev | cut -c 2- | rev | tac)
for y in $x; do
	losetup -d $y
done
}
