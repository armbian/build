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
	display_alert "Starting rootfs and image building process for" "$BOARD $RELEASE" "info"

	[[ $ROOTFS_TYPE != ext4 ]] && display_alert "Assuming $BOARD $BRANCH kernel supports $ROOTFS_TYPE" "" "wrn"

	# trap to unmount stuff in case of error/manual interruption
	trap unmount_on_exit INT TERM EXIT

	# stage: clean and create directories
	rm -rf $CACHEDIR/{$SDCARD,$MOUNT}
	mkdir -p $CACHEDIR/{$SDCARD,$MOUNT,rootfs} $DEST/images

	# stage: verify tmpfs configuration and mount
	# default maximum size for tmpfs mount is 1/2 of available RAM
	# CLI needs ~1.2GiB+ (Xenial CLI), Desktop - ~2.2GiB+ (Xenial Desktop w/o HW acceleration)
	# calculate and set tmpfs mount to use 2/3 of available RAM
	local phymem=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 * 2 / 3 )) # MiB
	if [[ $BUILD_DESKTOP == yes ]]; then local tmpfs_max_size=2500; else local tmpfs_max_size=1500; fi # MiB
	if [[ $FORCE_USE_RAMDISK == no ]]; then	local use_tmpfs=no
	elif [[ $FORCE_USE_RAMDISK == yes || $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi

	[[ $use_tmpfs == yes ]] && mount -t tmpfs -o size=${tmpfs_max_size}M tmpfs $CACHEDIR/$SDCARD

	# stage: prepare basic rootfs: unpack cache or create from scratch
	create_rootfs_cache

	# stage: install kernel and u-boot packages
	# install distribution and board specific applications

	mkdir -p $CACHEDIR/$SDCARD/tmp/debs
	mount --bind $DEST/debs/ $CACHEDIR/$SDCARD/tmp/debs

	install_distribution_specific
	install_common

	# install additional applications
	[[ $EXTERNAL == yes ]] && install_external_applications

	# install desktop files
	[[ $BUILD_DESKTOP == yes ]] && install_desktop

	# install locally built packages
	[[ $EXTERNAL_NEW == compile ]] && chroot_installpackages_local
	# install from apt.armbian.com
	[[ $EXTERNAL_NEW == prebuilt ]] && chroot_installpackages "yes"

	# cleanup for install_kernel and install_board_specific
	umount $CACHEDIR/$SDCARD/tmp/debs
	mountpoint -q $CACHEDIR/$SDCARD/tmp/debs || rm -rf $CACHEDIR/$SDCARD/tmp/debs

	# stage: user customization script
	# NOTE: installing too many packages may fill tmpfs mount
	customize_image

	# clean up / prepare for making the image
	umount_chroot "$CACHEDIR/$SDCARD"
	post_debootstrap_tweaks

	if [[ $ROOTFS_TYPE == fel ]]; then
		FEL_ROOTFS=$CACHEDIR/$SDCARD/
		display_alert "Starting FEL boot" "$BOARD" "info"
		source $SRC/lib/fel-load.sh
	else
		prepare_partitions
		create_image
	fi

	# stage: unmount tmpfs
	[[ $use_tmpfs = yes ]] && umount $CACHEDIR/$SDCARD

	rm -rf $CACHEDIR/$SDCARD

	# remove exit trap
	trap - INT TERM EXIT
} #############################################################################

# create_rootfs_cache
#
# unpacks cached rootfs for $RELEASE or creates one
#
create_rootfs_cache()
{
	local packages_hash=$(get_package_list_hash)
	local cache_fname=$CACHEDIR/rootfs/${RELEASE}-ng-$ARCH.$packages_hash.tar.lz4
	local display_name=${RELEASE}-ng-$ARCH.${packages_hash:0:3}...${packages_hash:29}.tar.lz4
	if [[ -f $cache_fname ]]; then
		local date_diff=$(( ($(date +%s) - $(stat -c %Y $cache_fname)) / 86400 ))
		display_alert "Extracting $display_name" "$date_diff days old" "info"
		pv -p -b -r -c -N "$display_name" "$cache_fname" | lz4 -dc | tar xp --xattrs -C $CACHEDIR/$SDCARD/
	else
		display_alert "Creating new rootfs for" "$RELEASE" "info"

		# stage: debootstrap base system
		if [[ $NO_APT_CACHER != yes ]]; then
			# apt-cacher-ng apt-get proxy parameter
			local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\""
			local apt_mirror="http://${APT_PROXY_ADDR:-localhost:3142}/$APT_MIRROR"
		else
			local apt_mirror="http://$APT_MIRROR"
		fi

		# fancy progress bars
		[[ -z $OUTPUT_DIALOG ]] && local apt_extra_progress="--show-progress -o DPKG::Progress-Fancy=1"

		display_alert "Installing base system" "Stage 1/2" "info"
		eval 'debootstrap --include=locales ${PACKAGE_LIST_EXCLUDE:+ --exclude=${PACKAGE_LIST_EXCLUDE// /,}} \
			--arch=$ARCH --foreign $RELEASE $CACHEDIR/$SDCARD/ $apt_mirror' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 1/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 || ! -f $CACHEDIR/$SDCARD/debootstrap/debootstrap ]] && exit_with_error "Debootstrap base system first stage failed"

		cp /usr/bin/$QEMU_BINARY $CACHEDIR/$SDCARD/usr/bin/

		mkdir -p $CACHEDIR/$SDCARD/usr/share/keyrings/
		cp /usr/share/keyrings/debian-archive-keyring.gpg $CACHEDIR/$SDCARD/usr/share/keyrings/

		display_alert "Installing base system" "Stage 2/2" "info"
		eval 'chroot $CACHEDIR/$SDCARD /bin/bash -c "/debootstrap/debootstrap --second-stage"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 2/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 || ! -f $CACHEDIR/$SDCARD/bin/bash ]] && exit_with_error "Debootstrap base system second stage failed"

		mount_chroot "$CACHEDIR/$SDCARD"

		# policy-rc.d script prevents starting or reloading services during image creation
		printf '#!/bin/sh\nexit 101' > $CACHEDIR/$SDCARD/usr/sbin/policy-rc.d
		chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/initctl"
		chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/start-stop-daemon"
		printf '#!/bin/sh\necho "Warning: Fake start-stop-daemon called, doing nothing"' > $CACHEDIR/$SDCARD/sbin/start-stop-daemon
		printf '#!/bin/sh\necho "Warning: Fake initctl called, doing nothing"' > $CACHEDIR/$SDCARD/sbin/initctl
		chmod 755 $CACHEDIR/$SDCARD/usr/sbin/policy-rc.d
		chmod 755 $CACHEDIR/$SDCARD/sbin/initctl
		chmod 755 $CACHEDIR/$SDCARD/sbin/start-stop-daemon

		# stage: configure language and locales
		display_alert "Configuring locales" "$DEST_LANG" "info"

		[[ -f $CACHEDIR/$SDCARD/etc/locale.gen ]] && sed -i "s/^# $DEST_LANG/$DEST_LANG/" $CACHEDIR/$SDCARD/etc/locale.gen
		eval 'LC_ALL=C LANG=C chroot $CACHEDIR/$SDCARD /bin/bash -c "locale-gen $DEST_LANG"' ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		eval 'LC_ALL=C LANG=C chroot $CACHEDIR/$SDCARD /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=$DEST_LANG"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		if [[ -f $CACHEDIR/$SDCARD/etc/default/console-setup ]]; then
			sed -e 's/CHARMAP=.*/CHARMAP="UTF-8"/' -e 's/FONTSIZE=.*/FONTSIZE="8x16"/' \
				-e 's/CODESET=.*/CODESET="guess"/' -i $CACHEDIR/$SDCARD/etc/default/console-setup
			eval 'LC_ALL=C LANG=C chroot $CACHEDIR/$SDCARD /bin/bash -c "setupcon --save"'
		fi

		# stage: create apt sources list
		create_sources_list "$RELEASE" "$CACHEDIR/$SDCARD/"

		# stage: add armbian repository and install key
		echo "deb http://apt.armbian.com $RELEASE main utils ${RELEASE}-desktop" > $CACHEDIR/$SDCARD/etc/apt/sources.list.d/armbian.list

		cp $SRC/lib/bin/armbian.key $CACHEDIR/$SDCARD
		eval 'chroot $CACHEDIR/$SDCARD /bin/bash -c "cat armbian.key | apt-key add -"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		rm $CACHEDIR/$SDCARD/armbian.key

		# add armhf arhitecture to arm64
		[[ $ARCH == arm64 ]] && eval 'LC_ALL=C LANG=C chroot $CACHEDIR/$SDCARD /bin/bash -c "dpkg --add-architecture armhf"'

		# stage: update packages list
		display_alert "Updating package list" "$RELEASE" "info"
		eval 'LC_ALL=C LANG=C chroot $CACHEDIR/$SDCARD /bin/bash -c "apt-get -q -y $apt_extra update"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Updating package lists..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		#[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Updating package lists failed"

		# stage: upgrade base packages from xxx-updates and xxx-backports repository branches
		display_alert "Upgrading base packages" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $CACHEDIR/$SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress upgrade"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Upgrading base packages..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		#[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Upgrading base packages failed"

		# stage: install additional packages
		display_alert "Installing packages for" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $CACHEDIR/$SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress --no-install-recommends install $PACKAGE_LIST"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing Armbian system..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Installation of Armbian packages failed"

		# DEBUG: print free space
		echo -e "\nFree space:"
		eval 'df -h | grep "$CACHEDIR/"' ${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'}

		# stage: remove downloaded packages
		chroot $CACHEDIR/$SDCARD /bin/bash -c "apt-get clean"

		# this is needed for the build process later since resolvconf generated file in /run is not saved
		rm $CACHEDIR/$SDCARD/etc/resolv.conf
		echo 'nameserver 8.8.8.8' >> $CACHEDIR/$SDCARD/etc/resolv.conf

		# stage: make rootfs cache archive
		display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
		sync
		# the only reason to unmount here is compression progress display
		# based on rootfs size calculation
		umount_chroot "$CACHEDIR/$SDCARD"

		tar cp --xattrs --directory=$CACHEDIR/$SDCARD/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | pv -p -b -r -s $(du -sb $CACHEDIR/$SDCARD/ | cut -f1) -N "$display_name" | lz4 -c > $cache_fname
	fi
	mount_chroot "$CACHEDIR/$SDCARD"
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
	# /boot: none, ext4, ext2, fat (BOOTFS_TYPE)
	# root: ext4, btrfs, f2fs, nfs (ROOTFS_TYPE)

	# declare makes local variables by default if used inside a function
	# NOTE: mountopts string should always start with comma if not empty

	# array copying in old bash versions is tricky, so having filesystems as arrays
	# with attributes as keys is not a good idea
	declare -A parttype mkopts mkfs mountopts

	parttype[ext4]=ext4
	parttype[ext2]=ext2
	parttype[fat]=fat16
	parttype[f2fs]=ext4 # not a copy-paste error
	parttype[btrfs]=btrfs
	# parttype[nfs] is empty

	# metadata_csum is supported since e2fsprogs 1.43
	local codename=$(lsb_release -sc)
	if [[ $codename == sid || $codename == stretch ]]; then
		mkopts[ext4]='-O ^64bit,^metadata_csum,uninit_bg -q -m 2'
	else
		mkopts[ext4]='-q -m 2'
	fi

	mkopts[fat]='-n BOOT'
	mkopts[ext2]='-q'
	# mkopts[f2fs] is empty
	# mkopts[btrfs] is empty
	# mkopts[nfs] is empty

	mkfs[ext4]=ext4
	mkfs[ext2]=ext2
	mkfs[fat]=vfat
	mkfs[f2fs]=f2fs
	mkfs[btrfs]=btrfs
	# mkfs[nfs] is empty

	mountopts[ext4]=',commit=600,errors=remount-ro'
	# mountopts[ext2] is empty
	# mountopts[fat] is empty
	# mountopts[f2fs] is empty
	# mountopts[btrfs] is empty
	# mountopts[nfs] is empty

	# stage: determine partition configuration
	if [[ -n $BOOTFS_TYPE ]]; then
		# 2 partition setup with forced /boot type
		local bootfs=$BOOTFS_TYPE
		local bootpart=1
		local rootpart=2
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=64 # MiB
	elif [[ $ROOTFS_TYPE != ext4 && $ROOTFS_TYPE != nfs ]]; then
		# 2 partition setup for non-ext4 local root
		local bootfs=ext4
		local bootpart=1
		local rootpart=2
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=64 # MiB
	elif [[ $ROOTFS_TYPE == nfs ]]; then
		# single partition ext4 /boot, no root
		local bootfs=ext4
		local bootpart=1
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=64 # MiB, For cleanup processing only
	else
		# single partition ext4 root
		local rootpart=1
		BOOTSIZE=0
	fi

	# stage: calculate rootfs size
	local rootfs_size=$(du -sm $CACHEDIR/$SDCARD/ | cut -f1) # MiB
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
		# Hardcoded overhead +40% and +128MB for ext4 is needed for desktop images, for CLI it can be lower
		# extra 128 MiB for emergency swap file
		local sdsize=$(bc -l <<< "scale=0; ($imagesize * 1.4) / 1 + 128")
	fi

	# stage: create blank image
	display_alert "Creating blank image for rootfs" "$sdsize MiB" "info"
	dd if=/dev/zero bs=1M status=none count=$sdsize | pv -p -b -r -s $(( $sdsize * 1024 * 1024 )) | dd status=none of=$CACHEDIR/${SDCARD}.raw

	# stage: calculate boot partition size
	local bootstart=$(($OFFSET * 2048))
	local rootstart=$(($bootstart + ($BOOTSIZE * 2048)))
	local bootend=$(($rootstart - 1))

	# stage: create partition table
	display_alert "Creating partitions" "${bootfs:+/boot: $bootfs }root: $ROOTFS_TYPE" "info"
	parted -s $CACHEDIR/${SDCARD}.raw -- mklabel msdos
	if [[ $ROOTFS_TYPE == nfs ]]; then
		# single /boot partition
		parted -s $CACHEDIR/${SDCARD}.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s -1s
	elif [[ $BOOTSIZE == 0 ]]; then
		# single root partition
		parted -s $CACHEDIR/${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s -1s
	else
		# /boot partition + root partition
		parted -s $CACHEDIR/${SDCARD}.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s ${bootend}s
		parted -s $CACHEDIR/${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s -1s
	fi

	# stage: mount image
	# lock access to loop devices
	exec {FD}>/var/lock/armbian-debootstrap-losetup
	flock -x $FD

	LOOP=$(losetup -f)
	[[ -z $LOOP ]] && exit_with_error "Unable to find free loop device"

	# NOTE: losetup -P option is not available in Trusty
	[[ $CONTAINER_COMPAT == yes && ! -e $LOOP ]] && mknod -m0660 $LOOP b 7 ${LOOP//\/dev\/loop} > /dev/null

	# TODO: Needs mknod here in Docker?
	losetup $LOOP $CACHEDIR/${SDCARD}.raw

	# loop device was grabbed here, unlock
	flock -u $FD

	partprobe $LOOP

	# stage: create fs, mount partitions, create fstab
	rm -f $CACHEDIR/$SDCARD/etc/fstab
	if [[ -n $rootpart ]]; then
		display_alert "Creating rootfs" "$ROOTFS_TYPE"
		[[ $CONTAINER_COMPAT == yes ]] && mknod -m0660 ${LOOP}p${rootpart} b 259 $rootpart > /dev/null
		mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} ${LOOP}p${rootpart}
		[[ $ROOTFS_TYPE == ext4 ]] && tune2fs -o journal_data_writeback ${LOOP}p${rootpart} > /dev/null
		[[ $ROOTFS_TYPE == btrfs ]] && local fscreateopt="-o compress-force=zlib"
		mount ${fscreateopt} ${LOOP}p${rootpart} $CACHEDIR/$MOUNT/
		local rootfs="UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart})"
		echo "$rootfs / ${mkfs[$ROOTFS_TYPE]} defaults,noatime,nodiratime${mountopts[$ROOTFS_TYPE]} 0 1" >> $CACHEDIR/$SDCARD/etc/fstab
	fi
	if [[ -n $bootpart ]]; then
		display_alert "Creating /boot" "$bootfs"
		[[ $CONTAINER_COMPAT == yes ]] && mknod -m0660 ${LOOP}p${bootpart} b 259 $bootpart > /dev/null
		mkfs.${mkfs[$bootfs]} ${mkopts[$bootfs]} ${LOOP}p${bootpart}
		mkdir -p $CACHEDIR/$MOUNT/boot/
		mount ${LOOP}p${bootpart} $CACHEDIR/$MOUNT/boot/
		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${bootpart}) /boot ${mkfs[$bootfs]} defaults${mountopts[$bootfs]} 0 2" >> $CACHEDIR/$SDCARD/etc/fstab
	fi
	[[ $ROOTFS_TYPE == nfs ]] && echo "/dev/nfs / nfs defaults 0 0" >> $CACHEDIR/$SDCARD/etc/fstab
	echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> $CACHEDIR/$SDCARD/etc/fstab

	# stage: adjust boot script or boot environment
	if [[ -f $CACHEDIR/$SDCARD/boot/armbianEnv.txt ]]; then
		if [[ $HAS_UUID_SUPPORT == yes ]]; then
			echo "rootdev=$rootfs" >> $CACHEDIR/$SDCARD/boot/armbianEnv.txt
		elif [[ $rootpart != 1 ]]; then
			echo "rootdev=/dev/mmcblk0p${rootpart}" >> $CACHEDIR/$SDCARD/boot/armbianEnv.txt
		fi
		echo "rootfstype=$ROOTFS_TYPE" >> $CACHEDIR/$SDCARD/boot/armbianEnv.txt
	elif [[ $rootpart != 1 ]]; then
		local bootscript_dst=${BOOTSCRIPT##*:}
		sed -i 's/mmcblk0p1/mmcblk0p2/' $CACHEDIR/$SDCARD/boot/$bootscript_dst
		sed -i -e "s/rootfstype=ext4/rootfstype=$ROOTFS_TYPE/" \
			-e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $CACHEDIR/$SDCARD/boot/$bootscript_dst
	fi

	# recompile .cmd to .scr if boot.cmd exists
	[[ -f $CACHEDIR/$SDCARD/boot/boot.cmd ]] && \
		mkimage -C none -A arm -T script -d $CACHEDIR/$SDCARD/boot/boot.cmd $CACHEDIR/$SDCARD/boot/boot.scr > /dev/null 2>&1

} #############################################################################

# create_image
#
# finishes creation of image from cached rootfs
#
create_image()
{
	# stage: create file name
	local version="Armbian_${REVISION}_${BOARD^}_${DISTRIBUTION}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}"
	[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
	[[ $ROOTFS_TYPE == nfs ]] && version=${version}_nfsboot

	if [[ $ROOTFS_TYPE != nfs ]]; then
		display_alert "Copying files to image" "${SDCARD}.raw" "info"
		rsync -aHWXh --exclude="/boot/*" --exclude="/dev/*" --exclude="/proc/*" --exclude="/run/*" --exclude="/tmp/*" \
			--exclude="/sys/*" --info=progress2,stats1 $CACHEDIR/$SDCARD/ $CACHEDIR/$MOUNT/
	else
		display_alert "Creating rootfs archive" "rootfs.tgz" "info"
		tar cp --xattrs --directory=$CACHEDIR/$SDCARD/ --exclude='./boot/*' --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | pv -p -b -r -s $(du -sb $CACHEDIR/$SDCARD/ | cut -f1) -N "rootfs.tgz" | gzip -c > $DEST/images/${version}-rootfs.tgz
	fi

	# stage: rsync /boot
	display_alert "Copying files to /boot partition" "${SDCARD}.raw" "info"
	if [[ $(findmnt --target $CACHEDIR/$MOUNT/boot -o FSTYPE -n) == vfat ]]; then
		# fat32
		rsync -rLtWh --info=progress2,stats1 $CACHEDIR/$SDCARD/boot $CACHEDIR/$MOUNT
	else
		# ext4
		rsync -aHWXh --info=progress2,stats1 $CACHEDIR/$SDCARD/boot $CACHEDIR/$MOUNT
	fi

	# DEBUG: print free space
	display_alert "Free space:" "SD card" "info"
	eval 'df -h | grep "$CACHEDIR/"' ${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'}

	# stage: write u-boot
	write_uboot $LOOP

	# unmount /boot first, rootfs second, image file last
	sync
	[[ $BOOTSIZE != 0 ]] && umount -l $CACHEDIR/$MOUNT/boot
	[[ $ROOTFS_TYPE != nfs ]] && umount -l $CACHEDIR/$MOUNT
	losetup -d $LOOP
	rm -rf --one-file-system $CACHEDIR/$DESTIMG $CACHEDIR/$MOUNT
	mkdir -p $CACHEDIR/$DESTIMG
	cp $CACHEDIR/$SDCARD/etc/armbian.txt $CACHEDIR/$DESTIMG
	mv $CACHEDIR/${SDCARD}.raw $CACHEDIR/$DESTIMG/${version}.img

	if [[ $COMPRESS_OUTPUTIMAGE == yes && $BUILD_ALL != yes ]]; then
		# compress image
		cd $CACHEDIR/$DESTIMG
        	sha256sum -b ${version}.img > sha256sum.sha
	        if [[ -n $GPG_PASS ]]; then
        	        echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes ${version}.img
                	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes armbian.txt
	        fi
			display_alert "Compressing" "$DEST/images/${version}.img" "info"
	        7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on $DEST/images/${version}.7z ${version}.img armbian.txt *.asc sha256sum.sha >/dev/null 2>&1
	fi
	#
	if [[ $BUILD_ALL != yes ]]; then
		mv $CACHEDIR/$DESTIMG/${version}.img $DEST/images/${version}.img
		rm -rf $CACHEDIR/$DESTIMG
	fi
	display_alert "Done building" "$DEST/images/${version}.img" "info"

} #############################################################################

# mount_chroot <target>
#
# helper to reduce code duplication
#
mount_chroot()
{
	local target=$1
	mount -t proc chproc $target/proc
	mount -t sysfs chsys $target/sys
	mount -t devtmpfs chdev $target/dev || mount --bind /dev $target/dev
	mount -t devpts chpts $target/dev/pts
} #############################################################################

# umount_chroot <target>
#
# helper to reduce code duplication
#
umount_chroot()
{
	local target=$1
	umount -l $target/dev/pts >/dev/null 2>&1
	umount -l $target/dev >/dev/null 2>&1
	umount -l $target/proc >/dev/null 2>&1
	umount -l $target/sys >/dev/null 2>&1
} #############################################################################

# unmount_on_exit
#
unmount_on_exit()
{
	trap - INT TERM EXIT
	umount_chroot "$CACHEDIR/$SDCARD/"
	umount -l $CACHEDIR/$SDCARD/tmp >/dev/null 2>&1
	umount -l $CACHEDIR/$SDCARD >/dev/null 2>&1
	umount -l $CACHEDIR/$MOUNT/boot >/dev/null 2>&1
	umount -l $CACHEDIR/$MOUNT >/dev/null 2>&1
	losetup -d $LOOP >/dev/null 2>&1
	umount -l $CACHEDIR/$SDCARD/tmp/debs >/dev/null 2>&1
	rm -rf --one-file-system $CACHEDIR/$SDCARD
	exit_with_error "debootstrap-ng was interrupted"
} #############################################################################
