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
	rm -rf $CACHEDIR/{sdcard,mount}
	mkdir -p $CACHEDIR/{sdcard,mount,rootfs} $DEST/images

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

	[[ $use_tmpfs == yes ]] && mount -t tmpfs -o size=${tmpfs_max_size}M tmpfs $CACHEDIR/sdcard

	# stage: prepare basic rootfs: unpack cache or create from scratch
	create_rootfs_cache

	# stage: install kernel and u-boot packages
	# install distribution and board specific applications

	mkdir -p $CACHEDIR/sdcard/tmp/debs
	mount --bind $DEST/debs/ $CACHEDIR/sdcard/tmp/debs

	install_distribution_specific
	install_common

	# install additional applications
	[[ $EXTERNAL == yes ]] && install_external_applications

	# install desktop files
	[[ $BUILD_DESKTOP == yes ]] && install_desktop

	if [[ $RELEASE == jessie || $RELEASE == xenial ]]; then
		# install locally built packages
		[[ $EXTERNAL_NEW == compile ]] && chroot_installpackages_local
		# install from apt.armbian.com
		[[ $EXTERNAL_NEW == prebuilt ]] && chroot_installpackages "yes"
	fi

	# cleanup for install_kernel and install_board_specific
	umount $CACHEDIR/sdcard/tmp/debs
	mountpoint -q $CACHEDIR/sdcard/tmp/debs || rm -rf $CACHEDIR/sdcard/tmp/debs

	# stage: user customization script
	# NOTE: installing too many packages may fill tmpfs mount
	customize_image

	# stage: cleanup
	rm -f $CACHEDIR/sdcard/sbin/initctl $CACHEDIR/sdcard/sbin/start-stop-daemon
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/initctl"
	chroot $CACHEDIR/sdcard /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/start-stop-daemon"
	rm -f $CACHEDIR/sdcard/usr/sbin/policy-rc.d $CACHEDIR/sdcard/usr/bin/$QEMU_BINARY

	umount_chroot "$CACHEDIR/sdcard"

	# to prevent creating swap file on NFS (needs specific kernel options)
	# and f2fs/btrfs (not recommended or needs specific kernel options)
	[[ $ROOTFS_TYPE != ext4 ]] && touch $CACHEDIR/sdcard/var/swap

	if [[ $ROOTFS_TYPE == fel ]]; then
		FEL_ROOTFS=$CACHEDIR/sdcard/
		display_alert "Starting FEL boot" "$BOARD" "info"
		source $SRC/lib/fel-load.sh
	else
		prepare_partitions
		create_image
	fi

	# stage: unmount tmpfs
	[[ $use_tmpfs = yes ]] && umount $CACHEDIR/sdcard

	rm -rf $CACHEDIR/sdcard

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
	local cache_fname=$CACHEDIR/rootfs/${RELEASE}-ng-$ARCH.$packages_hash.tgz
	local display_name=${RELEASE}-ng-$ARCH.${packages_hash:0:3}...${packages_hash:29}.tgz
	if [[ -f $cache_fname ]]; then
		local date_diff=$(( ($(date +%s) - $(stat -c %Y $cache_fname)) / 86400 ))
		display_alert "Extracting $display_name" "$date_diff days old" "info"
		pv -p -b -r -c -N "$display_name" "$cache_fname" | pigz -dc | tar xp --xattrs -C $CACHEDIR/sdcard/
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

		# fancy progress bars (except for Wheezy target)
		[[ -z $OUTPUT_DIALOG && $RELEASE != wheezy ]] && local apt_extra_progress="--show-progress -o DPKG::Progress-Fancy=1"

		display_alert "Installing base system" "Stage 1/2" "info"
		eval 'debootstrap --include=locales ${PACKAGE_LIST_EXCLUDE:+ --exclude=${PACKAGE_LIST_EXCLUDE// /,}} \
			--arch=$ARCH --foreign $RELEASE $CACHEDIR/sdcard/ $apt_mirror' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 1/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 || ! -f $CACHEDIR/sdcard/debootstrap/debootstrap ]] && exit_with_error "Debootstrap base system first stage failed"

		cp /usr/bin/$QEMU_BINARY $CACHEDIR/sdcard/usr/bin/

		mkdir -p $CACHEDIR/sdcard/usr/share/keyrings/
		cp /usr/share/keyrings/debian-archive-keyring.gpg $CACHEDIR/sdcard/usr/share/keyrings/

		display_alert "Installing base system" "Stage 2/2" "info"
		eval 'chroot $CACHEDIR/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 2/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 || ! -f $CACHEDIR/sdcard/bin/bash ]] && exit_with_error "Debootstrap base system second stage failed"

		mount_chroot "$CACHEDIR/sdcard"

		# policy-rc.d script prevents starting or reloading services during image creation
		printf '#!/bin/sh\nexit 101' > $CACHEDIR/sdcard/usr/sbin/policy-rc.d
		chroot $CACHEDIR/sdcard /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/initctl"
		chroot $CACHEDIR/sdcard /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/start-stop-daemon"
		printf '#!/bin/sh\necho "Warning: Fake start-stop-daemon called, doing nothing"' > $CACHEDIR/sdcard/sbin/start-stop-daemon
		printf '#!/bin/sh\necho "Warning: Fake initctl called, doing nothing"' > $CACHEDIR/sdcard/sbin/initctl
		chmod 755 $CACHEDIR/sdcard/usr/sbin/policy-rc.d
		chmod 755 $CACHEDIR/sdcard/sbin/initctl
		chmod 755 $CACHEDIR/sdcard/sbin/start-stop-daemon

		# stage: configure language and locales
		display_alert "Configuring locales" "$DEST_LANG" "info"

		[[ -f $CACHEDIR/sdcard/etc/locale.gen ]] && sed -i "s/^# $DEST_LANG/$DEST_LANG/" $CACHEDIR/sdcard/etc/locale.gen
		eval 'LC_ALL=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "locale-gen $DEST_LANG"' ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		eval 'LC_ALL=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=$DEST_LANG"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		if [[ -f $CACHEDIR/sdcard/etc/default/console-setup ]]; then
			sed -e 's/CHARMAP=.*/CHARMAP="UTF-8"/' -e 's/FONTSIZE=.*/FONTSIZE="8x16"/' \
				-e 's/CODESET=.*/CODESET="guess"/' -i $CACHEDIR/sdcard/etc/default/console-setup
			eval 'LC_ALL=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "setupcon --save"'
		fi

		# stage: create apt sources list
		create_sources_list "$RELEASE" "$CACHEDIR/sdcard/"

		# stage: add armbian repository and install key
		case $RELEASE in
		wheezy|trusty)
			echo "deb http://apt.armbian.com $RELEASE main" > $CACHEDIR/sdcard/etc/apt/sources.list.d/armbian.list
		;;
		jessie|xenial)
			echo "deb http://apt.armbian.com $RELEASE main utils ${RELEASE}-desktop" > $CACHEDIR/sdcard/etc/apt/sources.list.d/armbian.list
		;;
		esac
		cp $SRC/lib/bin/armbian.key $CACHEDIR/sdcard
		eval 'chroot $CACHEDIR/sdcard /bin/bash -c "cat armbian.key | apt-key add -"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		rm $CACHEDIR/sdcard/armbian.key

		# add armhf arhitecture to arm64
		[[ $ARCH == arm64 ]] && eval 'LC_ALL=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "dpkg --add-architecture armhf"'

		# stage: update packages list
		display_alert "Updating package list" "$RELEASE" "info"
		eval 'LC_ALL=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "apt-get -q -y $apt_extra update"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Updating package lists..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		#[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Updating package lists failed"

		# stage: upgrade base packages from xxx-updates and xxx-backports repository branches
		display_alert "Upgrading base packages" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress upgrade"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Upgrading base packages..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		#[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Upgrading base packages failed"

		# stage: install additional packages
		display_alert "Installing packages for" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $CACHEDIR/sdcard /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress --no-install-recommends install $PACKAGE_LIST"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing Armbian system..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Installation of Armbian packages failed"

		# DEBUG: print free space
		echo -e "\nFree space:"
		eval 'df -h | grep "$CACHEDIR/"' ${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'}

		# stage: remove downloaded packages
		chroot $CACHEDIR/sdcard /bin/bash -c "apt-get clean"

		# stage: make rootfs cache archive
		display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
		sync
		# the only reason to unmount here is compression progress display
		# based on rootfs size calculation
		umount_chroot "$CACHEDIR/sdcard"

		tar cp --xattrs --directory=$CACHEDIR/sdcard/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | pv -p -b -r -s $(du -sb $CACHEDIR/sdcard/ | cut -f1) -N "$display_name" | pigz --fast > $cache_fname
	fi
	mount_chroot "$CACHEDIR/sdcard"
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

	# metadata_csum is supported since e2fsprogs 1.43
	local codename=$(lsb_release -sc)
	if [[ $codename == sid || $codename == stretch ]]; then
		mkopts[ext4]='-O ^64bit,^metadata_csum,uninit_bg -q -m 2'
	else
		mkopts[ext4]='-q -m 2'
	fi

	mkopts[fat]='-n BOOT'
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
	local rootfs_size=$(du -sm $CACHEDIR/sdcard/ | cut -f1) # MiB
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
	dd if=/dev/zero bs=1M status=none count=$sdsize | pv -p -b -r -s $(( $sdsize * 1024 * 1024 )) | dd status=none of=$CACHEDIR/tmprootfs.raw

	# stage: determine partition configuration
	if [[ $BOOTSIZE != 0 ]]; then
		# fat32 /boot + ext4 or other root, deprecated
		local bootfs=fat
		local bootpart=1
		local rootpart=2
	elif [[ $ROOTFS_TYPE != ext4 && $ROOTFS_TYPE != nfs ]]; then
		# ext4 /boot + non-ext4 root
		BOOTSIZE=64 # MiB
		local bootfs=ext4
		local bootpart=1
		local rootpart=2
	elif [[ $ROOTFS_TYPE == nfs ]]; then
		# ext4 /boot, no root
		BOOTSIZE=64 # For cleanup processing only
		local bootfs=ext4
		local bootpart=1
	else
		# ext4 root
		local rootpart=1
	fi

	# stage: calculate boot partition size
	local bootstart=$(($OFFSET * 2048))
	local rootstart=$(($bootstart + ($BOOTSIZE * 2048)))
	local bootend=$(($rootstart - 1))

	# stage: create partition table
	display_alert "Creating partitions" "${bootfs:+/boot: $bootfs }root: $ROOTFS_TYPE" "info"
	parted -s $CACHEDIR/tmprootfs.raw -- mklabel msdos
	if [[ $ROOTFS_TYPE == nfs ]]; then
		# single /boot partition
		parted -s $CACHEDIR/tmprootfs.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s -1s
	elif [[ $BOOTSIZE == 0 ]]; then
		# single root partition
		parted -s $CACHEDIR/tmprootfs.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s -1s
	else
		# /boot partition + root partition
		parted -s $CACHEDIR/tmprootfs.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s ${bootend}s
		parted -s $CACHEDIR/tmprootfs.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s -1s
	fi

	# stage: mount image
	# TODO: Needs mknod here in Docker?
	LOOP=$(losetup -f)
	[[ -z $LOOP ]] && exit_with_error "Unable to find free loop device"

	# NOTE: losetup -P option is not available in Trusty
	[[ $CONTAINER_COMPAT == yes ]] && mknod -m0660 $LOOP b 7 ${LOOP//\/dev\/loop} > /dev/null

	losetup $LOOP $CACHEDIR/tmprootfs.raw
	partprobe $LOOP

	# stage: create fs, mount partitions, create fstab
	rm -f $CACHEDIR/sdcard/etc/fstab
	if [[ -n $rootpart ]]; then
		display_alert "Creating rootfs" "$ROOTFS_TYPE"
		[[ $CONTAINER_COMPAT == yes ]] && mknod -m0660 $LOOPp${rootpart} b 259 ${rootpart} > /dev/null
		mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} ${LOOP}p${rootpart}
		[[ $ROOTFS_TYPE == ext4 ]] && tune2fs -o journal_data_writeback ${LOOP}p${rootpart} > /dev/null
		[[ $ROOTFS_TYPE == btrfs ]] && local fscreateopt="-o compress=zlib"
		mount ${fscreateopt} ${LOOP}p${rootpart} $CACHEDIR/mount/
		local rootfs="UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart})"
		echo "$rootfs / ${mkfs[$ROOTFS_TYPE]} defaults,noatime,nodiratime${mountopts[$ROOTFS_TYPE]} 0 1" >> $CACHEDIR/sdcard/etc/fstab
	fi
	if [[ -n $bootpart ]]; then
		display_alert "Creating /boot" "$bootfs"
		[[ $CONTAINER_COMPAT == yes ]] && mknod -m0660 $LOOPp${bootpart} b 259 ${bootpart} > /dev/null
		mkfs.${mkfs[$bootfs]} ${mkopts[$bootfs]} ${LOOP}p${bootpart}
		mkdir -p $CACHEDIR/mount/boot/
		mount ${LOOP}p${bootpart} $CACHEDIR/mount/boot/
		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${bootpart}) /boot ${mkfs[$bootfs]} defaults${mountopts[$bootfs]} 0 2" >> $CACHEDIR/sdcard/etc/fstab
	fi
	[[ $ROOTFS_TYPE == nfs ]] && echo "/dev/nfs / nfs defaults 0 0" >> $CACHEDIR/sdcard/etc/fstab
	echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> $CACHEDIR/sdcard/etc/fstab

	# stage: adjust boot script or boot environment
	if [[ -f $CACHEDIR/sdcard/boot/armbianEnv.txt ]]; then
		if [[ $HAS_UUID_SUPPORT == yes ]]; then
			echo "rootdev=$rootfs" >> $CACHEDIR/sdcard/boot/armbianEnv.txt
		elif [[ $rootpart != 1 ]]; then
			echo "rootdev=/dev/mmcblk0p${rootpart}" >> $CACHEDIR/sdcard/boot/armbianEnv.txt
		fi
		echo "rootfstype=$ROOTFS_TYPE" >> $CACHEDIR/sdcard/boot/armbianEnv.txt
	elif [[ $rootpart != 1 ]]; then
		local bootscript_dst=${BOOTSCRIPT##*:}
		sed -i 's/mmcblk0p1/mmcblk0p2/' $CACHEDIR/sdcard/boot/$bootscript_dst
		sed -i -e "s/rootfstype=ext4/rootfstype=$ROOTFS_TYPE/" \
			-e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $CACHEDIR/sdcard/boot/$bootscript_dst
	fi

	# recompile .cmd to .scr if boot.cmd exists
	[[ -f $CACHEDIR/sdcard/boot/boot.cmd ]] && \
		mkimage -C none -A arm -T script -d $CACHEDIR/sdcard/boot/boot.cmd $CACHEDIR/sdcard/boot/boot.scr > /dev/null 2>&1

} #############################################################################

# create_image
#
# finishes creation of image from cached rootfs
#
create_image()
{
	# stage: create file name
	local version="Armbian_${REVISION}_${BOARD^}_${DISTRIBUTION}_${RELEASE}_${VER/-$LINUXFAMILY/}"
	[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
	[[ $ROOTFS_TYPE == nfs ]] && version=${version}_nfsboot

	if [[ $ROOTFS_TYPE != nfs ]]; then
		display_alert "Copying files to image" "tmprootfs.raw" "info"
		rsync -aHWXh --exclude="/boot/*" --exclude="/dev/*" --exclude="/proc/*" --exclude="/run/*" --exclude="/tmp/*" \
			--exclude="/sys/*" --info=progress2,stats1 $CACHEDIR/sdcard/ $CACHEDIR/mount/
	else
		display_alert "Creating rootfs archive" "rootfs.tgz" "info"
		tar cp --xattrs --directory=$CACHEDIR/sdcard/ --exclude='./boot/*' --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | pv -p -b -r -s $(du -sb $CACHEDIR/sdcard/ | cut -f1) -N "rootfs.tgz" | pigz > $DEST/images/${version}-rootfs.tgz
	fi

	# stage: rsync /boot
	display_alert "Copying files to /boot partition" "tmprootfs.raw" "info"
	if [[ $(findmnt --target $CACHEDIR/mount/boot -o FSTYPE -n) == vfat ]]; then
		# fat32
		rsync -rLtWh --info=progress2,stats1 $CACHEDIR/sdcard/boot $CACHEDIR/mount
	else
		# ext4
		rsync -aHWXh --info=progress2,stats1 $CACHEDIR/sdcard/boot $CACHEDIR/mount
	fi

	# DEBUG: print free space
	display_alert "Free space:" "SD card" "info"
	eval 'df -h | grep "$CACHEDIR/"' ${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'}

	# stage: write u-boot
	write_uboot $LOOP

	# unmount /boot first, rootfs second, image file last
	sync
	[[ $BOOTSIZE != 0 ]] && umount -l $CACHEDIR/mount/boot
	[[ $ROOTFS_TYPE != nfs ]] && umount -l $CACHEDIR/mount
	losetup -d $LOOP

	if [[ $BUILD_ALL == yes ]]; then
		TEMP_DIR="$(mktemp -d $CACHEDIR/${version}.XXXXXX)"
		cp $CACHEDIR/sdcard/etc/armbian.txt "${TEMP_DIR}/"
		mv "$CACHEDIR/tmprootfs.raw" "${TEMP_DIR}/${version}.img"
		cd "${TEMP_DIR}/"
		sign_and_compress &
	else
		cp $CACHEDIR/sdcard/etc/armbian.txt $CACHEDIR/
		mv $CACHEDIR/tmprootfs.raw $CACHEDIR/${version}.img
		cd $CACHEDIR/
		sign_and_compress
	fi
} #############################################################################

# sign_and_compress
#
# signs and compresses the image
#
sign_and_compress()
{
	# stage: compressing or copying image file
	if [[ $COMPRESS_OUTPUTIMAGE != yes ]]; then
		mv -f ${version}.img $DEST/images/${version}.img
		display_alert "Done building" "$DEST/images/${version}.img" "info"
	else
		display_alert "Signing and compressing" "Please wait!" "info"
		# stage: generate sha256sum
		sha256sum -b ${version}.img > sha256sum
		# stage: sign with PGP
		if [[ -n $GPG_PASS ]]; then
			echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes ${version}.img
			echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes armbian.txt
		fi
		if [[ $SEVENZIP == yes ]]; then
			local filename=$DEST/images/${version}.7z
			if [[ $BUILD_ALL == yes ]]; then
				nice -n 19 bash -c "7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on $filename ${version}.img armbian.txt *.asc sha256sum >/dev/null 2>&1 \
				; [[ -n '$SEND_TO_SERVER' ]] && rsync -arP $filename -e 'ssh -p 22' $SEND_TO_SERVER"
			else
				7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on $filename ${version}.img armbian.txt *.asc sha256sum >/dev/null 2>&1
				[[ -n $SEND_TO_SERVER ]] && rsync -arP $filename -e 'ssh -p 22' $SEND_TO_SERVER
			fi
		else
			local filename=$DEST/images/${version}.zip
			zip -FSq $filename ${version}.img armbian.txt *.asc sha256sum
		fi
		rm -f ${version}.img *.asc armbian.txt sha256sum
		if [[ $BUILD_ALL == yes ]]; then
			cd .. && rmdir "${TEMP_DIR}"
		else
			local filesize=$(ls -l --b=M $filename | cut -d " " -f5)
			display_alert "Done building" "$filename [$filesize]" "info"
		fi
	fi
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
	umount_chroot "$CACHEDIR/sdcard/"
	umount -l $CACHEDIR/sdcard/tmp >/dev/null 2>&1
	umount -l $CACHEDIR/sdcard >/dev/null 2>&1
	umount -l $CACHEDIR/mount/boot >/dev/null 2>&1
	umount -l $CACHEDIR/mount >/dev/null 2>&1
	losetup -d $LOOP >/dev/null 2>&1
	rm -rf $CACHEDIR/sdcard
	exit_with_error "debootstrap-ng was interrupted"
} #############################################################################
