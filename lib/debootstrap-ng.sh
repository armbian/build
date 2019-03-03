# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# debootstrap_ng
# create_rootfs_cache
# prepare_partitions
# update_initramfs
# create_image

# debootstrap_ng
#
debootstrap_ng()
{
	display_alert "Starting rootfs and image building process for" "$BOARD $RELEASE" "info"

	[[ $ROOTFS_TYPE != ext4 ]] && display_alert "Assuming $BOARD $BRANCH kernel supports $ROOTFS_TYPE" "" "wrn"

	# trap to unmount stuff in case of error/manual interruption
	trap unmount_on_exit INT TERM EXIT

	# stage: clean and create directories
	rm -rf $SDCARD $MOUNT
	mkdir -p $SDCARD $MOUNT $DEST/images $SRC/cache/rootfs

	# stage: verify tmpfs configuration and mount
	# default maximum size for tmpfs mount is 1/2 of available RAM
	# CLI needs ~1.2GiB+ (Xenial CLI), Desktop - ~2.8GiB+ (Xenial Desktop w/o HW acceleration)
	# calculate and set tmpfs mount to use 2/3 of available RAM
	local phymem=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 * 2 / 3 )) # MiB
	if [[ $BUILD_DESKTOP == yes ]]; then local tmpfs_max_size=3500; else local tmpfs_max_size=1500; fi # MiB
	if [[ $FORCE_USE_RAMDISK == no ]]; then	local use_tmpfs=no
	elif [[ $FORCE_USE_RAMDISK == yes || $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi
	[[ -n $FORCE_TMPFS_SIZE ]] && phymem=$FORCE_TMPFS_SIZE

	[[ $use_tmpfs == yes ]] && mount -t tmpfs -o size=${phymem}M tmpfs $SDCARD

	# stage: prepare basic rootfs: unpack cache or create from scratch
	create_rootfs_cache

	# stage: install kernel and u-boot packages
	# install distribution and board specific applications

	install_distribution_specific
	install_common

	# install additional applications
	[[ $EXTERNAL == yes ]] && install_external_applications

	# install locally built packages
	[[ $EXTERNAL_NEW == compile ]] && chroot_installpackages_local

	# install from apt.armbian.com
	[[ $EXTERNAL_NEW == prebuilt ]] && chroot_installpackages "yes"

	# stage: user customization script
	# NOTE: installing too many packages may fill tmpfs mount
	customize_image

	# clean up / prepare for making the image
	umount_chroot "$SDCARD"
	post_debootstrap_tweaks

	if [[ $ROOTFS_TYPE == fel ]]; then
		FEL_ROOTFS=$SDCARD/
		display_alert "Starting FEL boot" "$BOARD" "info"
		source $SRC/lib/fel-load.sh
	else
		prepare_partitions
		# update initramfs to reflect any configuration changes since kernel installation
		update_initramfs
		create_image
	fi

	# stage: unmount tmpfs
	[[ $use_tmpfs = yes ]] && umount $SDCARD

	rm -rf $SDCARD

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
	local cache_fname=$SRC/cache/rootfs/${RELEASE}-ng-$ARCH.$packages_hash.tar.lz4
	local display_name=${RELEASE}-ng-$ARCH.${packages_hash:0:3}...${packages_hash:29}.tar.lz4
	if [[ -f $cache_fname && "$ROOT_FS_CREATE_ONLY" != "force" ]]; then
		local date_diff=$(( ($(date +%s) - $(stat -c %Y $cache_fname)) / 86400 ))
		display_alert "Extracting $display_name" "$date_diff days old" "info"
		pv -p -b -r -c -N "$display_name" "$cache_fname" | lz4 -dc | tar xp --xattrs -C $SDCARD/
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
		eval 'debootstrap --include=${DEBOOTSTRAP_LIST} ${PACKAGE_LIST_EXCLUDE:+ --exclude=${PACKAGE_LIST_EXCLUDE// /,}} \
			--arch=$ARCH --components=${DEBOOTSTRAP_COMPONENTS} --foreign $RELEASE $SDCARD/ $apt_mirror' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 1/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 || ! -f $SDCARD/debootstrap/debootstrap ]] && exit_with_error "Debootstrap base system first stage failed"

		cp /usr/bin/$QEMU_BINARY $SDCARD/usr/bin/

		mkdir -p $SDCARD/usr/share/keyrings/
		cp /usr/share/keyrings/debian-archive-keyring.gpg $SDCARD/usr/share/keyrings/

		display_alert "Installing base system" "Stage 2/2" "info"
		eval 'chroot $SDCARD /bin/bash -c "/debootstrap/debootstrap --second-stage"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 2/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 || ! -f $SDCARD/bin/bash ]] && exit_with_error "Debootstrap base system second stage failed"

		mount_chroot "$SDCARD"

		# policy-rc.d script prevents starting or reloading services during image creation
		printf '#!/bin/sh\nexit 101' > $SDCARD/usr/sbin/policy-rc.d
		chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/initctl"
		chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/start-stop-daemon"
		printf '#!/bin/sh\necho "Warning: Fake start-stop-daemon called, doing nothing"' > $SDCARD/sbin/start-stop-daemon
		printf '#!/bin/sh\necho "Warning: Fake initctl called, doing nothing"' > $SDCARD/sbin/initctl
		chmod 755 $SDCARD/usr/sbin/policy-rc.d
		chmod 755 $SDCARD/sbin/initctl
		chmod 755 $SDCARD/sbin/start-stop-daemon

		# stage: configure language and locales
		display_alert "Configuring locales" "$DEST_LANG" "info"

		[[ -f $SDCARD/etc/locale.gen ]] && sed -i "s/^# $DEST_LANG/$DEST_LANG/" $SDCARD/etc/locale.gen
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "locale-gen $DEST_LANG"' ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=$DEST_LANG"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		if [[ -f $SDCARD/etc/default/console-setup ]]; then
			sed -e 's/CHARMAP=.*/CHARMAP="UTF-8"/' -e 's/FONTSIZE=.*/FONTSIZE="8x16"/' \
				-e 's/CODESET=.*/CODESET="guess"/' -i $SDCARD/etc/default/console-setup
			eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "setupcon --save"'
		fi

		# stage: create apt sources list
		create_sources_list "$RELEASE" "$SDCARD/"

		# stage: add armbian repository and install key
		echo "deb http://apt.armbian.com $RELEASE main ${RELEASE}-utils ${RELEASE}-desktop" > $SDCARD/etc/apt/sources.list.d/armbian.list

		cp $SRC/config/armbian.key $SDCARD
		eval 'chroot $SDCARD /bin/bash -c "cat armbian.key | apt-key add -"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		rm $SDCARD/armbian.key

		# compressing packages list to gain some space
		echo "Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";" > $SDCARD/etc/apt/apt.conf.d/02compress-indexes
		echo "Acquire::Languages "none";" > $SDCARD/etc/apt/apt.conf.d/no-languages

		# add armhf arhitecture to arm64
		[[ $ARCH == arm64 ]] && eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg --add-architecture armhf"'

		# this should fix resolvconf installation failure in some cases
		chroot $SDCARD /bin/bash -c 'echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections'

		# stage: update packages list
		display_alert "Updating package list" "$RELEASE" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "apt-get -q -y $apt_extra update"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Updating package lists..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		#[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Updating package lists failed"

		# stage: upgrade base packages from xxx-updates and xxx-backports repository branches
		display_alert "Upgrading base packages" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress upgrade"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Upgrading base packages..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		#[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Upgrading base packages failed"

		# stage: install additional packages
		display_alert "Installing packages for" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt -y -q \
			$apt_extra $apt_extra_progress --no-install-recommends install $PACKAGE_LIST"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing Armbian system..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Installation of Armbian packages failed"

		# DEBUG: print free space
		echo -e "\nFree space:"
		eval 'df -h' ${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'}

		# stage: remove downloaded packages
		chroot $SDCARD /bin/bash -c "apt-get clean"

		# this is needed for the build process later since resolvconf generated file in /run is not saved
		rm $SDCARD/etc/resolv.conf
		echo "nameserver $NAMESERVER" >> $SDCARD/etc/resolv.conf

		# stage: make rootfs cache archive
		display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
		sync
		# the only reason to unmount here is compression progress display
		# based on rootfs size calculation
		umount_chroot "$SDCARD"

		tar cp --xattrs --directory=$SDCARD/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | pv -p -b -r -s $(du -sb $SDCARD/ | cut -f1) -N "$display_name" | lz4 -c > $cache_fname

		# sign rootfs cache archive that it can be used for web cache once. Internal purposes
		if [[ -n $GPG_PASS ]]; then
			echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes $cache_fname
		fi

	fi

	# used for internal purposes. Faster rootfs cache rebuilding
    if [[ -n "$ROOT_FS_CREATE_ONLY" ]]; then
		[[ $use_tmpfs = yes ]] && umount $SDCARD
		rm -rf $SDCARD
		# remove exit trap
		trap - INT TERM EXIT
        exit
	fi

	mount_chroot "$SDCARD"
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

	# metadata_csum and 64bit may need to be disabled explicitly when migrating to newer supported host OS releases
	# TODO: Disable metadata_csum only for older releases (jessie)?
	if [[ $(lsb_release -sc) == bionic ]]; then
		mkopts[ext4]='-q -m 2 -O ^64bit,^metadata_csum'
	elif [[ $(lsb_release -sc) == xenial ]]; then
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
	mountopts[btrfs]=',commit=600,compress=lzo'
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
	elif [[ $CRYPTROOT_ENABLE == yes ]]; then
		# 2 partition setup for encrypted /root and non-encrypted /boot
		local bootfs=ext4
		local bootpart=1
		local rootpart=2
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=64 # MiB
	else
		# single partition ext4 root
		local rootpart=1
		BOOTSIZE=0
	fi

	# stage: calculate rootfs size
	local rootfs_size=$(du -sm $SDCARD/ | cut -f1) # MiB
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
		case $ROOTFS_TYPE in
			btrfs)
				# Used for server images, currently no swap functionality, so disk space
				# requirements are rather low since rootfs gets filled with compress-force=zlib
				local sdsize=$(bc -l <<< "scale=0; (($imagesize * 0.8) / 4 + 1) * 4")
				;;
			*)
				# Hardcoded overhead +25% is needed for desktop images,
				# for CLI it could be lower. Align the size up to 4MiB
				if [[ $BUILD_DESKTOP == yes ]]; then
					local sdsize=$(bc -l <<< "scale=0; ((($imagesize * 1.30) / 1 + 0) / 4 + 1) * 4")
				else
					local sdsize=$(bc -l <<< "scale=0; ((($imagesize * 1.25) / 1 + 0) / 4 + 1) * 4")
				fi
				;;
		esac
	fi

	# stage: create blank image
	display_alert "Creating blank image for rootfs" "$sdsize MiB" "info"
	dd if=/dev/zero bs=1M status=none count=$sdsize | pv -p -b -r -s $(( $sdsize * 1024 * 1024 )) | dd status=none of=${SDCARD}.raw

	# stage: calculate boot partition size
	local bootstart=$(($OFFSET * 2048))
	local rootstart=$(($bootstart + ($BOOTSIZE * 2048)))
	local bootend=$(($rootstart - 1))

	# stage: create partition table
	display_alert "Creating partitions" "${bootfs:+/boot: $bootfs }root: $ROOTFS_TYPE" "info"
	parted -s ${SDCARD}.raw -- mklabel msdos
	if [[ $ROOTFS_TYPE == nfs ]]; then
		# single /boot partition
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s -1s
	elif [[ $BOOTSIZE == 0 ]]; then
		# single root partition
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s -1s
	else
		# /boot partition + root partition
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s ${bootend}s
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s -1s
	fi

	# stage: mount image
	# lock access to loop devices
	exec {FD}>/var/lock/armbian-debootstrap-losetup
	flock -x $FD

	LOOP=$(losetup -f)
	[[ -z $LOOP ]] && exit_with_error "Unable to find free loop device"

	check_loop_device "$LOOP"

	# NOTE: losetup -P option is not available in Trusty
	losetup $LOOP ${SDCARD}.raw

	# loop device was grabbed here, unlock
	flock -u $FD

	partprobe $LOOP

	# stage: create fs, mount partitions, create fstab
	rm -f $SDCARD/etc/fstab
	if [[ -n $rootpart ]]; then
		local rootdevice="${LOOP}p${rootpart}"

		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			display_alert "Encrypting root partition with LUKS..." "cryptsetup luksFormat $rootdevice" ""
			echo -n $CRYPTROOT_PASSPHRASE | cryptsetup luksFormat $CRYPTROOT_PARAMETERS $rootdevice -
			echo -n $CRYPTROOT_PASSPHRASE | cryptsetup luksOpen $rootdevice $ROOT_MAPPER -
			display_alert "Root partition encryption complete." "" "ext"
			# TODO: pass /dev/mapper to Docker
			rootdevice=/dev/mapper/$ROOT_MAPPER # used by `mkfs` and `mount` commands
		fi

		check_loop_device "$rootdevice"
		display_alert "Creating rootfs" "$ROOTFS_TYPE on $rootdevice"
		mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} $rootdevice
		[[ $ROOTFS_TYPE == ext4 ]] && tune2fs -o journal_data_writeback $rootdevice > /dev/null
		[[ $ROOTFS_TYPE == btrfs ]] && local fscreateopt="-o compress-force=zlib"
		mount ${fscreateopt} $rootdevice $MOUNT/
		# create fstab (and crypttab) entry
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			# map the LUKS container partition via its UUID to be the 'cryptroot' device
			echo "$ROOT_MAPPER UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart}) none luks" >> $SDCARD/etc/crypttab
			local rootfs=$rootdevice # used in fstab
		else
			local rootfs="UUID=$(blkid -s UUID -o value $rootdevice)"
		fi
		echo "$rootfs / ${mkfs[$ROOTFS_TYPE]} defaults,noatime,nodiratime${mountopts[$ROOTFS_TYPE]} 0 1" >> $SDCARD/etc/fstab
	fi
	if [[ -n $bootpart ]]; then
		display_alert "Creating /boot" "$bootfs"
		check_loop_device "${LOOP}p${bootpart}"
		mkfs.${mkfs[$bootfs]} ${mkopts[$bootfs]} ${LOOP}p${bootpart}
		mkdir -p $MOUNT/boot/
		mount ${LOOP}p${bootpart} $MOUNT/boot/
		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${bootpart}) /boot ${mkfs[$bootfs]} defaults${mountopts[$bootfs]} 0 2" >> $SDCARD/etc/fstab
	fi
	[[ $ROOTFS_TYPE == nfs ]] && echo "/dev/nfs / nfs defaults 0 0" >> $SDCARD/etc/fstab
	echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> $SDCARD/etc/fstab

	# stage: adjust boot script or boot environment
	if [[ -f $SDCARD/boot/armbianEnv.txt ]]; then
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			echo "rootdev=$rootdevice cryptdevice=UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart}):$ROOT_MAPPER" >> $SDCARD/boot/armbianEnv.txt
		else
			echo "rootdev=$rootfs" >> $SDCARD/boot/armbianEnv.txt
		fi
		echo "rootfstype=$ROOTFS_TYPE" >> $SDCARD/boot/armbianEnv.txt
	elif [[ $rootpart != 1 ]]; then
		local bootscript_dst=${BOOTSCRIPT##*:}
		sed -i 's/mmcblk0p1/mmcblk0p2/' $SDCARD/boot/$bootscript_dst
		sed -i -e "s/rootfstype=ext4/rootfstype=$ROOTFS_TYPE/" \
			-e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $SDCARD/boot/$bootscript_dst
	fi

	# if we have boot.ini = remove armbianEnv.txt and add UUID there if enabled
	if [[ -f $SDCARD/boot/boot.ini ]]; then
		sed -i -e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $SDCARD/boot/boot.ini
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			local rootpart="UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart})"
			sed -i 's/^setenv rootdev .*/setenv rootdev "\/dev\/mapper\/'$ROOT_MAPPER' cryptdevice='$rootpart':'$ROOT_MAPPER'"/' $SDCARD/boot/boot.ini
		else
			sed -i 's/^setenv rootdev .*/setenv rootdev "'$rootfs'"/' $SDCARD/boot/boot.ini
		fi
		[[ -f $SDCARD/boot/armbianEnv.txt ]] && rm $SDCARD/boot/armbianEnv.txt
	fi

	# if we have a headless device, set console to DEFAULT_CONSOLE
	if [[ -n $DEFAULT_CONSOLE && -f $SDCARD/boot/armbianEnv.txt ]]; then
		if grep -lq "^console=" $SDCARD/boot/armbianEnv.txt; then
			sed -i "s/console=.*/console=$DEFAULT_CONSOLE/" $SDCARD/boot/armbianEnv.txt
		else
			echo "console=$DEFAULT_CONSOLE" >> $SDCARD/boot/armbianEnv.txt
        fi
	fi

	# recompile .cmd to .scr if boot.cmd exists
	[[ -f $SDCARD/boot/boot.cmd ]] && \
		mkimage -C none -A arm -T script -d $SDCARD/boot/boot.cmd $SDCARD/boot/boot.scr > /dev/null 2>&1

} #############################################################################

# update_initramfs
#
# this should be invoked as late as possible for any modifications by
# customize_image (userpatches) and prepare_partitions to be reflected in the
# final initramfs
#
# especially, this needs to be invoked after /etc/crypttab has been created
# for cryptroot-unlock to work:
# https://serverfault.com/questions/907254/cryproot-unlock-with-dropbear-timeout-while-waiting-for-askpass
#
update_initramfs() {

	update_initramfs_cmd="update-initramfs -uv -k ${VER}-${LINUXFAMILY}"
	display_alert "Updating initramfs..." "$update_initramfs_cmd" ""
	cp /usr/bin/$QEMU_BINARY $SDCARD/usr/bin/
	mount_chroot "$SDCARD/"

	chroot $SDCARD /bin/bash -c "$update_initramfs_cmd" >> $DEST/debug/install.log 2>&1
	display_alert "Updated initramfs." "for details see: $DEST/debug/install.log" "ext"

	umount_chroot "$SDCARD/"
	rm $SDCARD/usr/bin/$QEMU_BINARY

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
		display_alert "Copying files to root directory"
		rsync -aHWXh --exclude="/boot/*" --exclude="/dev/*" --exclude="/proc/*" --exclude="/run/*" --exclude="/tmp/*" \
			--exclude="/sys/*" --info=progress2,stats1 $SDCARD/ $MOUNT/
	else
		display_alert "Creating rootfs archive" "rootfs.tgz" "info"
		tar cp --xattrs --directory=$SDCARD/ --exclude='./boot/*' --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | pv -p -b -r -s $(du -sb $SDCARD/ | cut -f1) -N "rootfs.tgz" | gzip -c > $DEST/images/${version}-rootfs.tgz
	fi

	# stage: rsync /boot
	display_alert "Copying files to /boot directory"
	if [[ $(findmnt --target $MOUNT/boot -o FSTYPE -n) == vfat ]]; then
		# fat32
		rsync -rLtWh --info=progress2,stats1 $SDCARD/boot $MOUNT
	else
		# ext4
		rsync -aHWXh --info=progress2,stats1 $SDCARD/boot $MOUNT
	fi

	# DEBUG: print free space
	display_alert "Free space:" "SD card" "info"
	eval 'df -h' ${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'}

	# stage: write u-boot
	write_uboot $LOOP

	# fix wrong / permissions
	chmod 755 $MOUNT

	# unmount /boot first, rootfs second, image file last
	sync
	[[ $BOOTSIZE != 0 ]] && umount -l $MOUNT/boot
	[[ $ROOTFS_TYPE != nfs ]] && umount -l $MOUNT
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose $ROOT_MAPPER

	losetup -d $LOOP
	rm -rf --one-file-system $DESTIMG $MOUNT
	mkdir -p $DESTIMG
	cp $SDCARD/etc/armbian.txt $DESTIMG
	mv ${SDCARD}.raw $DESTIMG/${version}.img

	if [[ $COMPRESS_OUTPUTIMAGE == yes && $BUILD_ALL != yes ]]; then
		[[ -f $DEST/images/$CRYPTROOT_SSH_UNLOCK_KEY_NAME ]] && cp $DEST/images/$CRYPTROOT_SSH_UNLOCK_KEY_NAME $DESTIMG/
		# compress image
		cd $DESTIMG
		sha256sum -b ${version}.img > sha256sum.sha
		if [[ -n $GPG_PASS ]]; then
			echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${version}.img
		fi
			display_alert "Compressing" "$DEST/images/${version}.img" "info"
		7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on $DEST/images/${version}.7z ${version}.key ${version}.img armbian.txt *.asc sha256sum.sha >/dev/null 2>&1
	fi
	#
	if [[ $BUILD_ALL != yes ]]; then
		mv $DESTIMG/${version}.img $DEST/images/${version}.img
		rm -rf $DESTIMG
	fi
	display_alert "Done building" "$DEST/images/${version}.img" "info"

	# call custom post build hook
	[[ $(type -t post_build_image) == function ]] && post_build_image "$DEST/images/${version}.img"

	# write image to SD card
	if [[ $(lsblk "$CARD_DEVICE" 2>/dev/null) && -f $DEST/images/${version}.img && $COMPRESS_OUTPUTIMAGE != yes ]]; then
		display_alert "Writing image" "$CARD_DEVICE" "info"
		balena-etcher $DEST/images/${version}.img -d $CARD_DEVICE -y
		if [ $? -eq 0 ]; then
			display_alert "Writing succeeded" "${version}.img" "info"
			else
			display_alert "Writing failed" "${version}.img" "err"
		fi
	fi

} #############################################################################
