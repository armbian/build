# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

# Functions:
# debootstrap_ng
# create_rootfs_cache
# prepare_partitions
# create_image
# mount_chroot
# umount_chroot
# unmount_on_exit

# custom_debootstrap_ng
#
# main debootstrap function
#
debootstrap_ng()
{
	display_alert "Starting build process for" "$BOARD $RELEASE" "info"

	# default rootfs type is ext4
	[[ -z $ROOTFS_TYPE ]] && ROOTFS_TYPE=ext4

	[[ "ext4 f2fs btrfs nfs fel" != *"$ROOTFS_TYPE"* ]] && exit_with_error "Unknown rootfs type" "$ROOTFS_TYPE"

	# Fixed image size is in 1M dd blocks (MiB)
	# to get size of block device /dev/sdX execute as root:
	# echo $(( $(blockdev --getsize64 /dev/sdX) / 1024 / 1024 ))
	[[ "btrfs f2fs" == *"$ROOTFS_TYPE"* && -z $FIXED_IMAGE_SIZE ]] && exit_with_error "please define FIXED_IMAGE_SIZE"

	[[ $ROOTFS_TYPE != ext4 ]] && display_alert "Assuming $CHOOSEN_KERNEL supports $ROOTFS_TYPE" "" "wrn"

	# small SD card with kernel, boot scritpt and .dtb/.bin files
	[[ $ROOTFS_TYPE == nfs ]] && FIXED_IMAGE_SIZE=64

	# trap to unmount stuff in case of error/manual interruption
	trap unmount_on_exit INT TERM EXIT

	# stage: clean and create directories
	rm -rf $DEST/cache/sdcard $DEST/cache/mount
	mkdir -p $DEST/cache/sdcard $DEST/cache/mount $DEST/images

	# stage: verify tmpfs configuration and mount
	# default maximum size for tmpfs mount is 1/2 of available RAM
	# CLI needs ~1.2GiB+ (Xenial CLI), Desktop - ~2.2GiB+ (Xenial Desktop w/o HW acceleration)
	# calculate and set tmpfs mount to use 2/3 of available RAM
	local phymem=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 * 2 / 3 )) # MiB
	if [[ $BUILD_DESKTOP == yes ]]; then local tmpfs_max_size=2500; else local tmpfs_max_size=1500; fi # MiB
	if [[ $FORCE_USE_RAMDISK == no ]]; then
		local use_tmpfs=no
	elif [[ $FORCE_USE_RAMDISK == yes || $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi

	if [[ $use_tmpfs == yes ]]; then
		mount -t tmpfs -o size=${tmpfs_max_size}M tmpfs $DEST/cache/sdcard
	fi

	# stage: prepare basic rootfs: unpack cache or create from scratch
	create_rootfs_cache

	# stage: install kernel and u-boot packages
	# install distribution and board specific applications
	install_distribution_specific
	install_kernel
	install_board_specific

	# cleanup for install_kernel and install_board_specific
	umount $DEST/cache/sdcard/tmp

	# install desktop files
	if [[ $BUILD_DESKTOP == yes ]]; then
		install_desktop
	fi

	# install additional applications
	if [[ $EXTERNAL == yes ]]; then
		install_external_applications
	fi

	# stage: user customization script
	# NOTE: installing too many packages may fill tmpfs mount
	cp $SRC/userpatches/customize-image.sh $DEST/cache/sdcard/tmp/customize-image.sh
	chmod +x $DEST/cache/sdcard/tmp/customize-image.sh
	display_alert "Calling image customization script" "customize-image.sh" "info"
	chroot $DEST/cache/sdcard /bin/bash -c "/tmp/customize-image.sh $RELEASE $FAMILY $BOARD $BUILD_DESKTOP"

	# stage: cleanup
	rm -f $DEST/cache/sdcard/usr/sbin/policy-rc.d
	rm -f $DEST/cache/sdcard/usr/bin/qemu-arm-static
	if [[ -x $DEST/cache/sdcard/sbin/initctl.REAL ]]; then
		mv -f $DEST/cache/sdcard/sbin/initctl.REAL $DEST/cache/sdcard/sbin/initctl
	fi
	if [[ -x $DEST/cache/sdcard/sbin/start-stop-daemon.REAL ]]; then
		mv -f $DEST/cache/sdcard/sbin/start-stop-daemon.REAL $DEST/cache/sdcard/sbin/start-stop-daemon
	fi

	umount_chroot

	if [[ $ROOTFS_TYPE == fel ]]; then
		FEL_ROOTFS=$DEST/cache/sdcard/
		display_alert "Starting FEL boot" "$BOARD" "info"
		source $SRC/lib/fel-load.sh
	else
		prepare_partitions
		create_image
	fi

	# stage: unmount tmpfs
	if [[ $use_tmpfs = yes ]]; then
		umount $DEST/cache/sdcard
	fi

	rm -rf $DEST/cache/sdcard

	# remove exit trap
	trap - INT TERM EXIT
} #############################################################################

# create_rootfs_cache
#
# unpacks cached rootfs for $RELEASE or creates one
#
create_rootfs_cache()
{
	[[ $BUILD_DESKTOP == yes ]] && local variant_desktop=yes
	local packages_hash=$(get_package_list_hash $PACKAGE_LIST)
	local cache_fname="$DEST/cache/rootfs/$RELEASE${variant_desktop:+_desktop}-ng.$packages_hash.tgz"
	local display_name=$RELEASE${variant_desktop:+_desktop}-ng.${packages_hash:0:3}...${packages_hash:29}.tgz
	if [[ -f $cache_fname ]]; then
		local filemtime=$(stat -c %Y $cache_fname)
		local currtime=$(date +%s)
		local diff=$(( (currtime - filemtime) / 86400 ))
		display_alert "Extracting $display_name" "$diff days old" "info"
		pv -p -b -r -c -N "$display_name" "$cache_fname" | pigz -dc | tar xp -C $DEST/cache/sdcard/
	else
		display_alert "Creating new rootfs for" "$RELEASE" "info"

		# stage: debootstrap base system
		# apt-cacher-ng mirror configurarion
		[[ -n $APT_PROXY_ADDR ]] && display_alert "Using custom apt-cacher-ng address" "$APT_PROXY_ADDR" "info"
		if [[ $RELEASE == trusty || $RELEASE == xenial ]]; then
			local apt_mirror="http://${APT_PROXY_ADDR:-localhost:3142}/ports.ubuntu.com/"
		else
			local apt_mirror="http://${APT_PROXY_ADDR:-localhost:3142}/httpredir.debian.org/debian"
		fi
		# apt-cacher-ng apt-get proxy parameter
		local apt_extra='-o Acquire::http::Proxy="http://${APT_PROXY_ADDR:-localhost:3142}"'
		# fancy progress bars (except for Wheezy target)
		[[ -z $OUTPUT_DIALOG && $RELEASE != wheezy ]] && local apt_extra_progress="--show-progress -o DPKG::Progress-Fancy=1"

		display_alert "Installing base system" "Stage 1/2" "info"
		eval 'debootstrap --include=debconf-utils,locales --arch=armhf --foreign $RELEASE $DEST/cache/sdcard/ $apt_mirror' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 1/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Debootstrap base system first stage failed"

		cp /usr/bin/qemu-arm-static $DEST/cache/sdcard/usr/bin/
		# NOTE: not needed?
		mkdir -p $DEST/cache/sdcard/usr/share/keyrings/
		cp /usr/share/keyrings/debian-archive-keyring.gpg $DEST/cache/sdcard/usr/share/keyrings/

		display_alert "Installing base system" "Stage 2/2" "info"
		eval 'chroot $DEST/cache/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 2/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Debootstrap base system second stage failed"

		mount_chroot

		# policy-rc.d script prevents starting or reloading services
		# from dpkg pre- and post-install scripts during image creation

cat <<EOF > $DEST/cache/sdcard/usr/sbin/policy-rc.d
#!/bin/sh
exit 101
EOF
		chmod 755 $DEST/cache/sdcard/usr/sbin/policy-rc.d

		# ported from debootstrap and multistrap for upstart support
		if [[ -x $DEST/cache/sdcard/sbin/initctl ]]; then
			mv $DEST/cache/sdcard/sbin/start-stop-daemon $DEST/cache/sdcard/sbin/start-stop-daemon.REAL
cat <<EOF > $DEST/cache/sdcard/sbin/start-stop-daemon
#!/bin/sh
echo "Warning: Fake start-stop-daemon called, doing nothing"
EOF
			chmod 755 $DEST/cache/sdcard/sbin/start-stop-daemon
		fi

		if [[ -x $DEST/cache/sdcard/sbin/initctl ]]; then
			mv $DEST/cache/sdcard/sbin/initctl $DEST/cache/sdcard/sbin/initctl.REAL
cat <<EOF > $DEST/cache/sdcard/sbin/initctl
#!/bin/sh
echo "Warning: Fake initctl called, doing nothing"
EOF
			chmod 755 $DEST/cache/sdcard/sbin/initctl
		fi

		# stage: configure language and locales
		display_alert "Configuring locales" "$DEST_LANG" "info"

		if [ -f $DEST/cache/sdcard/etc/locale.gen ]; then sed -i "s/^# $DEST_LANG/$DEST_LANG/" $DEST/cache/sdcard/etc/locale.gen; fi
		eval 'LC_ALL=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "locale-gen $DEST_LANG"' ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		eval 'LC_ALL=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		LC_ALL=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "export CHARMAP=$CONSOLE_CHAR FONTFACE=8x16"

		# stage: copy proper apt sources list
		cp $SRC/lib/config/sources.list.$RELEASE $DEST/cache/sdcard/etc/apt/sources.list

		# stage: add armbian repository and install key
		echo "deb http://apt.armbian.com $RELEASE main" > $DEST/cache/sdcard/etc/apt/sources.list.d/armbian.list
		cp $SRC/lib/bin/armbian.key $DEST/cache/sdcard
		eval 'chroot $DEST/cache/sdcard /bin/bash -c "cat armbian.key | apt-key add -"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		rm $DEST/cache/sdcard/armbian.key

		# stage: update packages list
		display_alert "Updating package list" "$RELEASE" "info"
		eval 'LC_ALL=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "apt-get -y $apt_extra update"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Updating package lists..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		# stage: install additional packages
		display_alert "Installing packages for" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $DEST/cache/sdcard /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress --no-install-recommends install $PACKAGE_LIST"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing Armbian system..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Installation of Armbian packages failed"

		# DEBUG: print free space
		echo
		echo "Free space:"
		df -h | grep "$DEST/cache/" | tee -a $DEST/debug/debootstrap.log

		# stage: remove downloaded packages
		chroot $DEST/cache/sdcard /bin/bash -c "apt-get clean"

		# stage: make rootfs cache archive
		display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
		sync
		# the only reason to unmount here is compression progress display
		# based on rootfs size calculation
		umount_chroot

		tar cp --directory=$DEST/cache/sdcard/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | \
			pv -p -b -r -s $(du -sb $DEST/cache/sdcard/ | cut -f1) -N "$display_name" | pigz > $cache_fname
	fi
	mount_chroot
} #############################################################################

# prepare_partitions
#
# creates image file, partitions and fs
# and mounts it to local dir
# FS-dependent stuff (boot and root fs partition types) happens here
#
prepare_partitions()
{
	display_alert "Preparing image file for rootfs" "$BOARD $RELEASE" "info"

	# possible partition combinations
	# ext4 root only (BOOTSIZE == 0 && ROOTFS_TYPE == ext4)
	# ext4 boot + non-ext4 local root (BOOTSIZE == 0; ROOTFS_TYPE != ext4 or nfs)
	# fat32 boot + ext4 root (BOOTSIZE > 0 && ROOTFS_TYPE == ext4)
	# fat32 boot + non-ext4 local root (BOOTSIZE > 0; ROOTFS_TYPE != ext4 or nfs)
	# ext4 boot + NFS root (BOOTSIZE == 0; ROOTFS_TYPE == nfs)
	# fat32 boot + NFS root (BOOTSIZE > 0; ROOTFS_TYPE == nfs)

	# declare makes local variables by default if used inside a function
	# NOTE: mountopts string should always start with comma if not empty

	# array copying in old bash versions is tricky, so having filesystems as arrays
	# with attributes as keys is not a good idea
	declare -A parttype mkopts mkfs mountopts

	parttype[ext4]=ext4
	parttype[fat]=fat16
	parttype[f2fs]=ext4 # not a copy-paste error
	parttype[btrfs]=btrfs
	# parttype[nfs] is empty

	mkopts[ext4]='-q' # "-O journal_data_writeback" can be set here
	mkopts[fat]='-n boot'
	# mkopts[f2fs] is empty
	# mkopts[btrfs] is empty
	# mkopts[nfs] is empty

	mkfs[ext4]=ext4
	mkfs[fat]=vfat
	mkfs[f2fs]=f2fs
	mkfs[btrfs]=btrfs
	# mkfs[nfs] is empty

	mountopts[ext4]=',commit=600,errors=remount-ro'
	# mountopts[fat] is empty
	# mountopts[f2fs] is empty
	# mountopts[btrfs] is empty
	# mountopts[nfs] is empty

	# stage: calculate rootfs size
	local rootfs_size=$(du -sm $DEST/cache/sdcard/ | cut -f1) # MiB
	display_alert "Current rootfs size" "$rootfs_size MiB" "info"
	if [[ -n $FIXED_IMAGE_SIZE && $FIXED_IMAGE_SIZE =~ ^[0-9]+$ ]]; then
		display_alert "Using user-defined image size" "$FIXED_IMAGE_SIZE MiB" "info"
		local sdsize=$FIXED_IMAGE_SIZE
		# basic sanity check
		if [[ $ROOTFS_TYPE != nfs && $sdsize -lt $rootfs_size ]]; then
			exit_with_error "User defined image size is too small" "$sdsize <= $rootfs_size"
		fi
	else
		local imagesize=$(( $rootfs_size + $OFFSET + $BOOTSIZE )) # MiB
		# Hardcoded overhead +30% for ext4 leaves ~10% free on root partition
		# extra 128 MiB for emergency swap file
		local sdsize=$(bc -l <<< "scale=0; ($imagesize * 1.3) / 1 + 128")
	fi

	# stage: create blank image
	display_alert "Creating blank image for rootfs" "$sdsize MiB" "info"
	dd if=/dev/zero bs=1M status=none count=$sdsize | pv -p -b -r -s $(( $sdsize * 1024 * 1024 )) | dd status=none of=$DEST/cache/tmprootfs.raw

	# stage: determine partition configuration
	# boot
	if [[ $ROOTFS_TYPE != ext4 && $BOOTSIZE == 0 ]]; then
		local bootfs=ext4
		BOOTSIZE=32 # MiB
	elif [[ $BOOTSIZE != 0 ]]; then
		local bootfs=fat
		BOOTSIZE=64 # MiB, fix for rsync duplicating zImage
	fi

	# stage: calculate boot partition size
	BOOTSTART=$(($OFFSET * 2048))
	ROOTSTART=$(($BOOTSTART + ($BOOTSIZE * 2048)))
	BOOTEND=$(($ROOTSTART - 1))

	# stage: create partition table
	display_alert "Creating partitions" "${bootfs:+/boot: $bootfs }root: $ROOTFS_TYPE" "info"
	parted -s $DEST/cache/tmprootfs.raw -- mklabel msdos
	if [[ $ROOTFS_TYPE == nfs ]]; then
		parted -s $DEST/cache/tmprootfs.raw -- mkpart primary ${parttype[$bootfs]} ${BOOTSTART}s -1s
	elif [[ $BOOTSIZE == 0 ]]; then
		parted -s $DEST/cache/tmprootfs.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${ROOTSTART}s -1s
	else
		parted -s $DEST/cache/tmprootfs.raw -- mkpart primary ${parttype[$bootfs]} ${BOOTSTART}s ${BOOTEND}s
		parted -s $DEST/cache/tmprootfs.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${ROOTSTART}s -1s
	fi

	# stage: mount image
	LOOP=$(losetup -f)
	if [[ -z $LOOP ]]; then
		# NOTE: very unlikely with this debootstrap process
		exit_with_error "Unable to find free loop device"
	fi

	# NOTE: losetup -P option is not available in Trusty
	losetup $LOOP $DEST/cache/tmprootfs.raw
	partprobe $LOOP

	# stage: create fs
	if [[ $BOOTSIZE == 0 ]]; then
		eval mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} ${LOOP}p1 ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
	else
		if [[ $ROOTFS_TYPE != nfs ]]; then
			eval mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} ${LOOP}p2 ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		fi
		eval mkfs.${mkfs[$bootfs]} ${mkopts[$bootfs]} ${LOOP}p1 ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
	fi

	# stage: mount partitions and create proper fstab
	rm -f $DEST/cache/sdcard/etc/fstab
	if [[ $BOOTSIZE == 0 ]]; then
		mount ${LOOP}p1 $DEST/cache/mount/
		echo "/dev/mmcblk0p1 / ${parttype[$ROOTFS_TYPE]} defaults,noatime,nodiratime${mountopts[$ROOTFS_TYPE]} 0 1" >> $DEST/cache/sdcard/etc/fstab
	else
		if [[ $ROOTFS_TYPE != nfs ]]; then
			mount ${LOOP}p2 $DEST/cache/mount/
			echo "/dev/mmcblk0p2 / ${parttype[$ROOTFS_TYPE]} defaults,noatime,nodiratime${mountopts[$ROOTFS_TYPE]} 0 1" >> $DEST/cache/sdcard/etc/fstab
		fi
		# create /boot on rootfs after it is mounted
		mkdir -p $DEST/cache/mount/boot/
		mount ${LOOP}p1 $DEST/cache/mount/boot/
		echo "/dev/mmcblk0p1 /boot ${parttype[$bootfs]} defaults${mountopts[$bootfs]} 0 2" >> $DEST/cache/sdcard/etc/fstab
	fi
	echo "tmpfs /tmp tmpfs defaults,rw,nosuid 0 0" >> $DEST/cache/sdcard/etc/fstab

	# stage: create boot script
	if [[ $ROOTFS_TYPE == nfs ]]; then
		# copy script provided by user if exists
		if [[ -f $SRC/userpatches/nfs-boot.cmd ]]; then
			display_alert "Using custom NFS boot script" "userpatches/nfs-boot.cmd" "info"
			cp $SRC/userpatches/nfs-boot.cmd $DEST/cache/sdcard/boot/boot.cmd
		else
			cp $SRC/lib/scripts/nfs-boot.cmd.template $DEST/cache/sdcard/boot/boot.cmd
		fi
	elif [[ $BOOTSIZE != 0 ]]; then
		sed -i 's/mmcblk0p1/mmcblk0p2/' $DEST/cache/sdcard/boot/boot.cmd
		sed -i "s/rootfstype=ext4/rootfstype=$ROOTFS_TYPE/" $DEST/cache/sdcard/boot/boot.cmd
	fi
	mkimage -C none -A arm -T script -d $DEST/cache/sdcard/boot/boot.cmd $DEST/cache/sdcard/boot/boot.scr > /dev/null 2>&1

} #############################################################################

# create_image
#
# finishes creation of image from cached rootfs
#
create_image()
{
	# stage: create file name
	VER=${VER/-$LINUXFAMILY/}
	VERSION=$VERSION" "$VER
	VERSION=${VERSION// /_}
	VERSION=${VERSION//$BRANCH/}
	VERSION=${VERSION//__/_}
	[[ $BUILD_DESKTOP == yes ]] && VERSION=${VERSION}_desktop
	[[ $ROOTFS_TYPE == nfs ]] && VERSION=${VERSION}_nfsboot

	if [[ $ROOTFS_TYPE != nfs ]]; then
		display_alert "Copying files to image" "tmprootfs.raw" "info"
		eval 'rsync -aHWh --exclude="/boot/*" --exclude="/dev/*" --exclude="/proc/*" --exclude="/run/*" --exclude="/tmp/*" \
			--exclude="/sys/*" --info=progress2,stats1 $DEST/cache/sdcard/ $DEST/cache/mount/'
	else
		# to prevent creating swap file on NFS share as it needs special kernel config option turned on
		touch $DEST/cache/sdcard/var/swap

		# kill /etc/network/interfaces on target to prevent conflicts between kernel
		# and userspace network config (mainly on Xenial)
		rm -f $FEL_ROOTFS/etc/network/interfaces
		printf "auto lo\niface lo inet loopback" > $FEL_ROOTFS/etc/network/interfaces

		display_alert "Creating rootfs archive" "rootfs.tgz" "info"
		tar cp --directory=$DEST/cache/sdcard/ --exclude='./boot/*' --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | \
			pv -p -b -r -s $(du -sb $DEST/cache/sdcard/ | cut -f1) -N "rootfs.tgz" | pigz > $DEST/images/$VERSION-rootfs.tgz
	fi

	# stage: rsync /boot
	display_alert "Copying files to /boot partition" "tmprootfs.raw" "info"
	if [[ $(findmnt --target $DEST/cache/mount/boot -o FSTYPE -n) == vfat ]]; then
		# fat32
		rsync -rLtWh --info=progress2,stats1 $DEST/cache/sdcard/boot $DEST/cache/mount
	else
		# ext4
		rsync -aHWh --info=progress2,stats1 $DEST/cache/sdcard/boot $DEST/cache/mount
	fi

	# DEBUG: print free space
	echo
	echo "Free space:"
	df -h | grep "$DEST/cache/" | tee -a $DEST/debug/debootstrap.log

	# stage: write u-boot
	write_uboot $LOOP

	# stage: copy armbian.txt TODO: Copy only if creating zip file?
	cp $DEST/cache/sdcard/etc/armbian.txt $DEST/cache/

	# unmount /boot first, rootfs second, image file last
	if [[ $BOOTSIZE != 0 ]]; then umount -l $DEST/cache/mount/boot; fi
	if [[ $ROOTFS_TYPE != nfs ]]; then umount -l $DEST/cache/mount; fi
	losetup -d $LOOP

	mv $DEST/cache/tmprootfs.raw $DEST/cache/$VERSION.raw
	cd $DEST/cache/

	# stage: compressing or copying image file
	if [[ -n $FIXED_IMAGE_SIZE || $COMPRESS_OUTPUTIMAGE == no ]]; then
		display_alert "Copying image file" "$VERSION.raw" "info"
		mv -f $DEST/cache/$VERSION.raw $DEST/images/$VERSION.raw
		display_alert "Done building" "$DEST/images/$VERSION.raw" "info"
	else
		display_alert "Signing and compressing" "$VERSION.zip" "info"
		# stage: sign with PGP
		if [[ -n $GPG_PASS ]]; then
			echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes $VERSION.raw
			echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes armbian.txt
		fi
		zip -FSq $DEST/images/$VERSION.zip $VERSION.raw* armbian.txt
		rm -f $VERSION.raw *.asc armbian.txt
		display_alert "Done building" "$DEST/images/$VERSION.zip" "info"
	fi
} #############################################################################

# mount_chroot
#
# helper to reduce code duplication
#
mount_chroot()
{
	mount -t proc chproc $DEST/cache/sdcard/proc
	mount -t sysfs chsys $DEST/cache/sdcard/sys
	mount -t devtmpfs chdev $DEST/cache/sdcard/dev || mount --bind /dev $DEST/cache/sdcard/dev
	mount -t devpts chpts $DEST/cache/sdcard/dev/pts
} #############################################################################

# umount_chroot
#
# helper to reduce code duplication
#
umount_chroot()
{
	umount -l $DEST/cache/sdcard/dev/pts >/dev/null 2>&1
	umount -l $DEST/cache/sdcard/dev >/dev/null 2>&1
	umount -l $DEST/cache/sdcard/proc >/dev/null 2>&1
	umount -l $DEST/cache/sdcard/sys >/dev/null 2>&1
} #############################################################################

# unmount_on_exit
#
unmount_on_exit()
{
	umount_chroot
	umount -l $DEST/cache/sdcard >/dev/null 2>&1
	umount -l $DEST/cache/mount/boot >/dev/null 2>&1
	umount -l $DEST/cache/mount >/dev/null 2>&1
	losetup -d $LOOP >/dev/null 2>&1
	rm -rf $DEST/cache/sdcard
	exit_with_error "debootstrap-ng was interrupted"
} #############################################################################
