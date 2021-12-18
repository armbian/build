#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Armbian build script
# https://github.com/armbian/build/

function build_rootfs_image() {
	display_alert "Starting rootfs and image building process for" "${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}" "info"

	[[ $ROOTFS_TYPE != ext4 ]] && display_alert "Assuming $BOARD $BRANCH kernel supports $ROOTFS_TYPE" "" "wrn"

	# trap to unmount stuff in case of error/manual interruption
	trap unmount_on_exit INT TERM EXIT

	# stage: clean and create directories
	rm -rf $SDCARD $MOUNT
	mkdir -p $SDCARD $MOUNT $DEST/images $SRC/cache/rootfs

	# bind mount rootfs if defined
	if [[ -d "${ARMBIAN_CACHE_ROOTFS_PATH}" ]]; then
		mountpoint -q "${SRC}"/cache/rootfs && umount -l "${SRC}"/cache/toolchain
		mount --bind "${ARMBIAN_CACHE_ROOTFS_PATH}" "${SRC}"/cache/rootfs
	fi

	# stage: verify tmpfs configuration and mount
	# CLI needs ~1.5GiB, desktop - ~3.5GiB
	# calculate and set tmpfs mount to use 9/10 of available RAM+SWAP
	local phymem=$(((($(awk '/MemTotal/ {print $2}' /proc/meminfo) + $(awk '/SwapTotal/ {print $2}' /proc/meminfo))) / 1024 * 9 / 10)) # MiB
	if [[ $BUILD_DESKTOP == yes ]]; then local tmpfs_max_size=3500; else local tmpfs_max_size=1500; fi                                 # MiB
	if [[ $FORCE_USE_RAMDISK == no ]]; then
		local use_tmpfs=no
	elif [[ $FORCE_USE_RAMDISK == yes || $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi
	[[ -n $FORCE_TMPFS_SIZE ]] && phymem=$FORCE_TMPFS_SIZE

	[[ $use_tmpfs == yes ]] && mount -t tmpfs -o size=${phymem}M tmpfs $SDCARD

	# stage: prepare basic rootfs: unpack cache or create from scratch
	LOG_SECTION="create_rootfs_cache" do_with_logging create_rootfs_cache

	call_extension_method "pre_install_distribution_specific" "config_pre_install_distribution_specific" << 'PRE_INSTALL_DISTRIBUTION_SPECIFIC'
*give config a chance to act before install_distribution_specific*
Called after `create_rootfs_cache` (_prepare basic rootfs: unpack cache or create from scratch_) but before `install_distribution_specific` (_install distribution and board specific applications_).
PRE_INSTALL_DISTRIBUTION_SPECIFIC

	# stage: install kernel and u-boot packages
	# install distribution and board specific applications

	LOG_SECTION="distro" do_with_logging install_distribution_specific
	LOG_SECTION="install_common" do_with_logging install_common

	# install locally built packages
	[[ $EXTERNAL_NEW == compile ]] && LOG_SECTION="packages_local" do_with_logging chroot_installpackages_local

	# install from apt.armbian.com
	[[ $EXTERNAL_NEW == prebuilt ]] && LOG_SECTION="packages_prebuilt" do_with_logging chroot_installpackages "yes"

	# stage: user customization script
	# NOTE: installing too many packages may fill tmpfs mount
	LOG_SECTION="custom" do_with_logging customize_image

	# remove packages that are no longer needed. rootfs cache + uninstall might have leftovers.
	LOG_SECTION="rootfs_apt_get_autoremove" do_with_logging apt_purge_unneeded_packages

	# create list of installed packages for debug purposes
	chroot $SDCARD /bin/bash -c "dpkg --get-selections" | grep -v deinstall | awk '{print $1}' | cut -f1 -d':' > $DEST/${LOG_SUBPATH}/installed-packages-${RELEASE}$([[ ${BUILD_MINIMAL} == yes ]] && echo "-minimal")$([[ ${BUILD_DESKTOP} == yes ]] && echo "-desktop").list.log 2>&1

	# clean up / prepare for making the image
	umount_chroot "$SDCARD"
	LOG_SECTION="post_debootstrap_tweaks" post_debootstrap_tweaks

	if [[ $ROOTFS_TYPE == fel ]]; then
		FEL_ROOTFS=$SDCARD/
		display_alert "Starting FEL boot" "$BOARD" "info"
		start_fel_boot
	else
		LOG_SECTION="partitioning" do_with_logging prepare_partitions
		LOG_SECTION="image" do_with_logging create_image
	fi

	# stage: unmount tmpfs
	umount $SDCARD 2>&1
	if [[ $use_tmpfs = yes ]]; then
		while grep -qs "$SDCARD" /proc/mounts; do
			umount $SDCARD
			sleep 5
		done
	fi
	rm -rf $SDCARD

	# remove exit trap
	trap - INT TERM EXIT
} #############################################################################

# create_rootfs_cache
#
# unpacks cached rootfs for $RELEASE or creates one
#

# this is under the logging manager. so just log to stdout (no redirections), and redirect stderr to stdout unless you want it on screen.
prepare_partitions() {
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
	parttype[xfs]=xfs
	# parttype[nfs] is empty

	# metadata_csum and 64bit may need to be disabled explicitly when migrating to newer supported host OS releases
	# add -N number of inodes to keep mount from running out
	# create bigger number for desktop builds
	if [[ $BUILD_DESKTOP == yes ]]; then local node_number=4096; else local node_number=1024; fi
	if [[ $HOSTRELEASE =~ bionic|buster|bullseye|cosmic|focal|hirsute|impish|jammy|sid ]]; then
		mkopts[ext4]="-q -m 2 -O ^64bit,^metadata_csum -N $((128 * ${node_number}))"
	elif [[ $HOSTRELEASE == xenial ]]; then
		mkopts[ext4]="-q -m 2 -N $((128 * ${node_number}))"
	fi
	mkopts[fat]='-n BOOT'
	mkopts[ext2]='-q'
	# mkopts[f2fs] is empty
	mkopts[btrfs]='-m dup'
	# mkopts[xfs] is empty
	# mkopts[nfs] is empty

	mkfs[ext4]=ext4
	mkfs[ext2]=ext2
	mkfs[fat]=vfat
	mkfs[f2fs]=f2fs
	mkfs[btrfs]=btrfs
	mkfs[xfs]=xfs
	# mkfs[nfs] is empty

	mountopts[ext4]=',commit=600,errors=remount-ro'
	# mountopts[ext2] is empty
	# mountopts[fat] is empty
	# mountopts[f2fs] is empty
	mountopts[btrfs]=',commit=600'
	# mountopts[xfs] is empty
	# mountopts[nfs] is empty

	# default BOOTSIZE to use if not specified
	DEFAULT_BOOTSIZE=256 # MiB
	# size of UEFI partition. 0 for no UEFI. Don't mix UEFISIZE>0 and BOOTSIZE>0
	UEFISIZE=${UEFISIZE:-0}
	BIOSSIZE=${BIOSSIZE:-0}
	UEFI_MOUNT_POINT=${UEFI_MOUNT_POINT:-/boot/efi}
	UEFI_FS_LABEL="${UEFI_FS_LABEL:-armbiefi}"

	call_extension_method "pre_prepare_partitions" "prepare_partitions_custom" << 'PRE_PREPARE_PARTITIONS'
*allow custom options for mkfs*
Good time to change stuff like mkfs opts, types etc.
PRE_PREPARE_PARTITIONS

	# stage: determine partition configuration
	if [[ -n $BOOTFS_TYPE ]]; then
		# 2 partition setup with forced /boot type
		local bootfs=$BOOTFS_TYPE
		local bootpart=1
		local rootpart=2
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE}
	elif [[ $ROOTFS_TYPE != ext4 && $ROOTFS_TYPE != nfs ]]; then
		# 2 partition setup for non-ext4 local root
		local bootfs=ext4
		local bootpart=1
		local rootpart=2
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE}
	elif [[ $ROOTFS_TYPE == nfs ]]; then
		# single partition ext4 /boot, no root
		local bootfs=ext4
		local bootpart=1
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE} # For cleanup processing only
	elif [[ $CRYPTROOT_ENABLE == yes ]]; then
		# 2 partition setup for encrypted /root and non-encrypted /boot
		local bootfs=ext4
		local bootpart=1
		local rootpart=2
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE}
	elif [[ $UEFISIZE -gt 0 ]]; then
		if [[ "${IMAGE_PARTITION_TABLE}" == "gpt" ]]; then
			# efi partition and ext4 root. some juggling is done by parted/sgdisk
			local uefipart=15
			local rootpart=1
		else
			# efi partition and ext4 root.
			local uefipart=1
			local rootpart=2
		fi
	else
		# single partition ext4 root
		local rootpart=1
		BOOTSIZE=0
	fi

	# stage: calculate rootfs size
	export rootfs_size=$(du -sm $SDCARD/ | cut -f1) # MiB
	display_alert "Current rootfs size" "$rootfs_size MiB" "info"

	call_extension_method "prepare_image_size" "config_prepare_image_size" << 'PREPARE_IMAGE_SIZE'
*allow dynamically determining the size based on the $rootfs_size*
Called after `${rootfs_size}` is known, but before `${FIXED_IMAGE_SIZE}` is taken into account.
A good spot to determine `FIXED_IMAGE_SIZE` based on `rootfs_size`.
UEFISIZE can be set to 0 for no UEFI partition, or to a size in MiB to include one.
Last chance to set `USE_HOOK_FOR_PARTITION`=yes and then implement create_partition_table hook_point.
PREPARE_IMAGE_SIZE

	if [[ -n $FIXED_IMAGE_SIZE && $FIXED_IMAGE_SIZE =~ ^[0-9]+$ ]]; then
		display_alert "Using user-defined image size" "$FIXED_IMAGE_SIZE MiB" "info"
		local sdsize=$FIXED_IMAGE_SIZE
		# basic sanity check
		if [[ $ROOTFS_TYPE != nfs && $sdsize -lt $rootfs_size ]]; then
			exit_with_error "User defined image size is too small" "$sdsize <= $rootfs_size"
		fi
	else
		local imagesize=$(($rootfs_size + $OFFSET + $BOOTSIZE + $UEFISIZE + $EXTRA_ROOTFS_MIB_SIZE)) # MiB
		case $ROOTFS_TYPE in
			btrfs)
				# Used for server images, currently no swap functionality, so disk space
				if [[ $BTRFS_COMPRESSION == none ]]; then
					local sdsize=$(bc -l <<< "scale=0; (($imagesize * 1.25) / 4 + 1) * 4")
				else
					# requirements are rather low since rootfs gets filled with compress-force=zlib
					local sdsize=$(bc -l <<< "scale=0; (($imagesize * 0.8) / 4 + 1) * 4")
				fi
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
	if [[ $FAST_CREATE_IMAGE == yes ]]; then
		truncate --size=${sdsize}M ${SDCARD}.raw # sometimes results in fs corruption, revert to previous know to work solution
		sync
	else
		dd if=/dev/zero bs=1M status=none count=$sdsize |
			pv -p -b -r -s $(($sdsize * 1024 * 1024)) -N "$(logging_echo_prefix_for_pv "zero") zero" |
			dd status=none of=${SDCARD}.raw
	fi

	# stage: calculate boot partition size
	local bootstart=$(($OFFSET * 2048))
	local rootstart=$(($bootstart + ($BOOTSIZE * 2048) + ($UEFISIZE * 2048)))
	local bootend=$(($rootstart - 1))

	# stage: create partition table
	display_alert "Creating partitions" "${bootfs:+/boot: $bootfs }root: $ROOTFS_TYPE" "info"
	parted -s ${SDCARD}.raw -- mklabel ${IMAGE_PARTITION_TABLE}
	if [[ "${USE_HOOK_FOR_PARTITION}" == "yes" ]]; then
		call_extension_method "create_partition_table" <<- 'CREATE_PARTITION_TABLE'
			*only called when USE_HOOK_FOR_PARTITION=yes to create the complete partition table*
			Finally, we can get our own partition table. You have to partition ${SDCARD}.raw
			yourself. Good luck.
		CREATE_PARTITION_TABLE
	elif [[ $ROOTFS_TYPE == nfs ]]; then
		# single /boot partition
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s "100%"
	elif [[ $UEFISIZE -gt 0 ]]; then
		# uefi partition + root partition
		if [[ "${IMAGE_PARTITION_TABLE}" == "gpt" ]]; then
			if [[ ${BIOSSIZE} -gt 0 ]]; then
				display_alert "Creating partitions" "BIOS+UEFI+rootfs" "info"
				# UEFI + GPT automatically get a BIOS partition at 14, EFI at 15
				local biosstart=$(($OFFSET * 2048))
				local uefistart=$(($OFFSET * 2048 + ($BIOSSIZE * 2048)))
				local rootstart=$(($uefistart + ($UEFISIZE * 2048)))
				local biosend=$(($uefistart - 1))
				local uefiend=$(($rootstart - 1))
				parted -s ${SDCARD}.raw -- mkpart bios fat32 ${biosstart}s ${biosend}s
				parted -s ${SDCARD}.raw -- mkpart efi fat32 ${uefistart}s ${uefiend}s
				parted -s ${SDCARD}.raw -- mkpart rootfs ${parttype[$ROOTFS_TYPE]} ${rootstart}s "100%"
				# transpose so BIOS is in sda14; EFI is in sda15 and root in sda1; requires sgdisk, parted cant do numbers
				sgdisk --transpose 1:14 ${SDCARD}.raw &> /dev/null || echo "*** TRANSPOSE 1:14 FAILED"
				sgdisk --transpose 2:15 ${SDCARD}.raw &> /dev/null || echo "*** TRANSPOSE 2:15 FAILED"
				sgdisk --transpose 3:1 ${SDCARD}.raw &> /dev/null || echo "*** TRANSPOSE 3:1 FAILED"
				# set the ESP (efi) flag on 15
				parted -s ${SDCARD}.raw -- set 14 bios_grub on || echo "*** SETTING bios_grub ON 14 FAILED"
				parted -s ${SDCARD}.raw -- set 15 esp on || echo "*** SETTING ESP ON 15 FAILED"
			else
				display_alert "Creating partitions" "UEFI+rootfs (no BIOS)" "info"
				# Simple EFI + root partition on GPT, no BIOS.
				parted -s ${SDCARD}.raw -- mkpart efi fat32 ${bootstart}s ${bootend}s
				parted -s ${SDCARD}.raw -- mkpart rootfs ${parttype[$ROOTFS_TYPE]} ${rootstart}s "100%"
				# transpose so EFI is in sda15 and root in sda1; requires sgdisk, parted cant do numbers
				sgdisk --transpose 1:15 ${SDCARD}.raw &> /dev/null || echo "*** TRANSPOSE 1:15 FAILED"
				sgdisk --transpose 2:1 ${SDCARD}.raw &> /dev/null || echo "*** TRANSPOSE 2:1 FAILED"
				# set the ESP (efi) flag on 15
				parted -s ${SDCARD}.raw -- set 15 esp on || echo "*** SETTING ESP ON 15 FAILED"
			fi
		else
			parted -s ${SDCARD}.raw -- mkpart primary fat32 ${bootstart}s ${bootend}s
			parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s "100%"
		fi
	elif [[ $BOOTSIZE == 0 ]]; then
		# single root partition
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s "100%"
	else
		# /boot partition + root partition
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s ${bootend}s
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s "100%"
	fi

	call_extension_method "post_create_partitions" <<- 'POST_CREATE_PARTITIONS'
		*called after all partitions are created, but not yet formatted*
	POST_CREATE_PARTITIONS

	# stage: mount image
	# lock access to loop devices
	exec {FD}> /var/lock/armbian-debootstrap-losetup
	flock -x $FD

	export LOOP=$(losetup -f) || exit_with_error "Unable to find free loop device"
	display_alert "Allocated loop device" "LOOP=${LOOP}" "wrn"

	check_loop_device "$LOOP"

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
		mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} $rootdevice 2>&1
		[[ $ROOTFS_TYPE == ext4 ]] && tune2fs -o journal_data_writeback $rootdevice > /dev/null
		if [[ $ROOTFS_TYPE == btrfs && $BTRFS_COMPRESSION != none ]]; then
			local fscreateopt="-o compress-force=${BTRFS_COMPRESSION}"
		fi
		mount ${fscreateopt} $rootdevice $MOUNT/
		# create fstab (and crypttab) entry
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			# map the LUKS container partition via its UUID to be the 'cryptroot' device
			echo "$ROOT_MAPPER UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart}) none luks" >> $SDCARD/etc/crypttab
			local rootfs=$rootdevice # used in fstab
		else
			local rootfs="UUID=$(blkid -s UUID -o value $rootdevice)"
		fi
		echo "$rootfs / ${mkfs[$ROOTFS_TYPE]} defaults,noatime${mountopts[$ROOTFS_TYPE]} 0 1" >> $SDCARD/etc/fstab
	fi
	if [[ -n $bootpart ]]; then
		display_alert "Creating /boot" "$bootfs on ${LOOP}p${bootpart}"
		check_loop_device "${LOOP}p${bootpart}"
		mkfs.${mkfs[$bootfs]} ${mkopts[$bootfs]} ${LOOP}p${bootpart} 2>&1
		mkdir -p $MOUNT/boot/
		mount ${LOOP}p${bootpart} $MOUNT/boot/
		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${bootpart}) /boot ${mkfs[$bootfs]} defaults${mountopts[$bootfs]} 0 2" >> $SDCARD/etc/fstab
	fi
	if [[ -n $uefipart ]]; then
		display_alert "Creating EFI partition" "FAT32 ${UEFI_MOUNT_POINT} on ${LOOP}p${uefipart} label ${UEFI_FS_LABEL}"
		check_loop_device "${LOOP}p${uefipart}"
		mkfs.fat -F32 -n "${UEFI_FS_LABEL}" ${LOOP}p${uefipart} 2>&1
		mkdir -p "${MOUNT}${UEFI_MOUNT_POINT}"
		mount ${LOOP}p${uefipart} "${MOUNT}${UEFI_MOUNT_POINT}"
		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${uefipart}) ${UEFI_MOUNT_POINT} vfat defaults 0 2" >> $SDCARD/etc/fstab
	fi
	[[ $ROOTFS_TYPE == nfs ]] && echo "/dev/nfs / nfs defaults 0 0" >> $SDCARD/etc/fstab
	echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> $SDCARD/etc/fstab

	call_extension_method "format_partitions" <<- 'FORMAT_PARTITIONS'
		*if you created your own partitions, this would be a good time to format them*
		The loop device is mounted, so ${LOOP}p1 is it's first partition etc.
	FORMAT_PARTITIONS

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
		if [[ $LINUXFAMILY != meson64 ]]; then
			[[ -f $SDCARD/boot/armbianEnv.txt ]] && rm $SDCARD/boot/armbianEnv.txt
		fi
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
	[[ -f $SDCARD/boot/boot.cmd ]] &&
		mkimage -C none -A arm -T script -d $SDCARD/boot/boot.cmd $SDCARD/boot/boot.scr > /dev/null 2>&1

	# create extlinux config
	if [[ -f $SDCARD/boot/extlinux/extlinux.conf ]]; then
		echo "  APPEND root=$rootfs $SRC_CMDLINE $MAIN_CMDLINE" >> $SDCARD/boot/extlinux/extlinux.conf
		[[ -f $SDCARD/boot/armbianEnv.txt ]] && rm $SDCARD/boot/armbianEnv.txt
	fi

}
#############################################################################

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
# since Debian buster, it has to be called within create_image() on the $MOUNT
# path instead of $SDCARD (which can be a tmpfs and breaks cryptsetup-initramfs).
# see: https://github.com/armbian/build/issues/1584
#
# @TODO: logging?
update_initramfs() {
	local chroot_target=$1
	local target_dir="$(find "${chroot_target}/lib/modules"/ -maxdepth 1 -type d -name "*${VER}*")"
	if [ "$target_dir" != "" ]; then
		update_initramfs_cmd="update-initramfs -uv -k $(basename "$target_dir")"
	else
		exit_with_error "No kernel installed for the version" "${VER}"
	fi
	display_alert "Updating initramfs..." "$update_initramfs_cmd" ""
	cp "/usr/bin/$QEMU_BINARY" "$chroot_target/usr/bin"/
	mount_chroot "$chroot_target/"

	chroot_custom_long_running "$chroot_target" "$update_initramfs_cmd" || {
		exit_with_error "Updating initramfs FAILED"
	}
	display_alert "Updated initramfs." "${update_initramfs_cmd}" "info"

	display_alert "Re-enabling" "initramfs-tools hook for kernel"
	chroot "$chroot_target" /bin/bash -c "chmod -v +x /etc/kernel/postinst.d/initramfs-tools" 2>&1

	umount_chroot "$chroot_target/"
	rm $chroot_target/usr/bin/$QEMU_BINARY

} #############################################################################

# create_image
#
# finishes creation of image from cached rootfs
#
create_image() {
	# create DESTIMG, hooks might put stuff there early.
	mkdir -p $DESTIMG

	# stage: create file name
	local version="${VENDOR}_${REVISION}_${BOARD^}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}${DESKTOP_ENVIRONMENT:+_$DESKTOP_ENVIRONMENT}"
	[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
	[[ $BUILD_MINIMAL == yes ]] && version=${version}_minimal
	[[ $ROOTFS_TYPE == nfs ]] && version=${version}_nfsboot

	if [[ $ROOTFS_TYPE != nfs ]]; then
		display_alert "Copying files to" "/"
		rsync -aHWXh \
			--exclude="/boot/*" \
			--exclude="/dev/*" \
			--exclude="/proc/*" \
			--exclude="/run/*" \
			--exclude="/tmp/*" \
			--exclude="/sys/*" \
			--info=progress0,stats1 $SDCARD/ $MOUNT/ 2>&1
	else
		display_alert "Creating rootfs archive" "rootfs.tgz" "info"
		tar cp --xattrs --directory=$SDCARD/ --exclude='./boot/*' --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . |
			pv -p -b -r -s "$(du -sb "$SDCARD"/ | cut -f1)" \
				-N "$(logging_echo_prefix_for_pv "create_rootfs_archive") rootfs.tgz" |
			gzip -c > "$DEST/images/${version}-rootfs.tgz"
	fi

	# stage: rsync /boot
	display_alert "Copying files to" "/boot"
	if [[ $(findmnt --target $MOUNT/boot -o FSTYPE -n) == vfat ]]; then
		# fat32
		rsync -rLtWh \
			--info=progress0,stats1 \
			--log-file="${DEST}"/${LOG_SUBPATH}/install.log $SDCARD/boot $MOUNT 2>&1 #@TODO: log to stdout, terse?
	else
		# ext4
		rsync -aHWXh \
			--info=progress0,stats1 \
			--log-file="${DEST}"/${LOG_SUBPATH}/install.log $SDCARD/boot $MOUNT 2>&1 #@TODO: log to stdout, terse?
	fi

	call_extension_method "pre_update_initramfs" "config_pre_update_initramfs" << 'PRE_UPDATE_INITRAMFS'
*allow config to hack into the initramfs create process*
Called after rsync has synced both `/root` and `/root` on the target, but before calling `update_initramfs`.
PRE_UPDATE_INITRAMFS

	# stage: create final initramfs
	[[ -n $KERNELSOURCE ]] && {
		update_initramfs $MOUNT
	}

	# DEBUG: print free space
	local freespace=$(LC_ALL=C df -h)
	# @TODO: this is very specific; we don't want it on screen ever?
	#echo $freespace >> $DEST/${LOG_SUBPATH}/debootstrap.log
	display_alert "Free SD cache" "$(echo -e "$freespace" | grep $SDCARD | awk '{print $5}')" "info"
	display_alert "Mount point" "$(echo -e "$freespace" | grep $MOUNT | head -1 | awk '{print $5}')" "info"

	# stage: write u-boot, unless the deb is not there, which would happen if BOOTCONFIG=none
	[[ -f "${DEB_STORAGE}"/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb ]] && write_uboot $LOOP

	# fix wrong / permissions
	chmod 755 $MOUNT

	call_extension_method "pre_umount_final_image" "config_pre_umount_final_image" << 'PRE_UMOUNT_FINAL_IMAGE'
*allow config to hack into the image before the unmount*
Called before unmounting both `/root` and `/boot`.
PRE_UMOUNT_FINAL_IMAGE

	# unmount /boot/efi first, then /boot, rootfs third, image file last
	sync
	[[ $UEFISIZE != 0 ]] && umount -l "${MOUNT}${UEFI_MOUNT_POINT}"
	[[ $BOOTSIZE != 0 ]] && umount -l $MOUNT/boot
	[[ $ROOTFS_TYPE != nfs ]] && umount -l $MOUNT
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose $ROOT_MAPPER

	call_extension_method "post_umount_final_image" "config_post_umount_final_image" << 'POST_UMOUNT_FINAL_IMAGE'
*allow config to hack into the image after the unmount*
Called after unmounting both `/root` and `/boot`.
POST_UMOUNT_FINAL_IMAGE

	# to make sure its unmounted
	while grep -Eq '(${MOUNT}|${DESTIMG})' /proc/mounts; do
		display_alert "Wait for unmount" "${MOUNT}" "info"
		sleep 5
	done

	display_alert "Freeing loop device" "${LOOP}" "wrn"
	losetup -d "${LOOP}"
	# Don't delete $DESTIMG here, extensions might have put nice things there already.
	rm -rf --one-file-system $MOUNT

	mkdir -p $DESTIMG
	mv ${SDCARD}.raw $DESTIMG/${version}.img

	FINALDEST=$DEST/images
	[[ "${BUILD_ALL}" == yes ]] && MAKE_FOLDERS="yes"

	if [[ "${MAKE_FOLDERS}" == yes ]]; then
		if [[ "$RC" == yes ]]; then
			FINALDEST=$DEST/images/"${BOARD}"/RC
		elif [[ "$BETA" == yes ]]; then
			FINALDEST=$DEST/images/"${BOARD}"/nightly
		else
			FINALDEST=$DEST/images/"${BOARD}"/archive
		fi
		install -d ${FINALDEST}
	fi

	# custom post_build_image_modify hook to run before fingerprinting and compression
	[[ $(type -t post_build_image_modify) == function ]] && display_alert "Custom Hook Detected" "post_build_image_modify" "info" && post_build_image_modify "${DESTIMG}/${version}.img"

	if [[ -z $SEND_TO_SERVER ]]; then

		if [[ $COMPRESS_OUTPUTIMAGE == "" || $COMPRESS_OUTPUTIMAGE == no ]]; then
			COMPRESS_OUTPUTIMAGE="sha,gpg,img"
		elif [[ $COMPRESS_OUTPUTIMAGE == yes ]]; then
			COMPRESS_OUTPUTIMAGE="sha,gpg,7z"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *gz* ]]; then
			display_alert "Compressing" "${DESTIMG}/${version}.img.gz" "info"
			pigz -3 < $DESTIMG/${version}.img > $DESTIMG/${version}.img.gz
			compression_type=".gz"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *xz* ]]; then
			display_alert "Compressing" "${DESTIMG}/${version}.img.xz" "info"
			# compressing consumes a lot of memory we don't have. Waiting for previous packing job to finish helps to run a lot more builds in parallel
			available_cpu=$(grep -c 'processor' /proc/cpuinfo)
			#[[ ${BUILD_ALL} == yes ]] && available_cpu=$(( $available_cpu * 30 / 100 )) # lets use 20% of resources in case of build-all
			[[ ${available_cpu} -gt 16 ]] && available_cpu=16                                               # using more cpu cores for compressing is pointless
			available_mem=$(LC_ALL=c free | grep Mem | awk '{print $4/$2 * 100.0}' | awk '{print int($1)}') # in percentage
			# build optimisations when memory drops below 5%
			if [[ ${BUILD_ALL} == yes && (${available_mem} -lt 15 || $(ps -uax | grep "pixz" | wc -l) -gt 4) ]]; then
				while [[ $(ps -uax | grep "pixz" | wc -l) -gt 2 ]]; do
					echo -en "#"
					sleep 20
				done
			fi
			pixz -7 -p ${available_cpu} -f $(expr ${available_cpu} + 2) < $DESTIMG/${version}.img > ${DESTIMG}/${version}.img.xz
			compression_type=".xz"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *img* || $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
			#			mv $DESTIMG/${version}.img ${FINALDEST}/${version}.img || exit 1
			compression_type=""
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *sha* ]]; then
			cd ${DESTIMG}
			display_alert "SHA256 calculating" "${version}.img${compression_type}" "info"
			sha256sum -b ${version}.img${compression_type} > ${version}.img${compression_type}.sha
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *gpg* ]]; then
			cd ${DESTIMG}
			if [[ -n $GPG_PASS ]]; then
				display_alert "GPG signing" "${version}.img${compression_type}" "info"
				if [[ -n $SUDO_USER ]]; then
					sudo chown -R ${SUDO_USER}:${SUDO_USER} "${DESTIMG}"/
					SUDO_PREFIX="sudo -H -u ${SUDO_USER}"
				else
					SUDO_PREFIX=""
				fi
				echo "${GPG_PASS}" | $SUDO_PREFIX bash -c "gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${DESTIMG}/${version}.img${compression_type}" || exit 1
			else
				display_alert "GPG signing skipped - no GPG_PASS" "${version}.img" "wrn"
			fi
		fi

		fingerprint_image "${DESTIMG}/${version}.img${compression_type}.txt" "${version}"

		if [[ $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
			display_alert "Compressing" "${DESTIMG}/${version}.7z" "info"
			7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on \
				${DESTIMG}/${version}.7z ${version}.key ${version}.img* > /dev/null 2>&1
			find ${DESTIMG}/ -type \
				f \( -name "${version}.img" -o -name "${version}.img.asc" -o -name "${version}.img.txt" -o -name "${version}.img.sha" \) -print0 |
				xargs -0 rm > /dev/null 2>&1
		fi

	fi
	display_alert "Done building" "${DESTIMG}/${version}.img" "info"

	# Previously, post_build_image passed the .img path as an argument to the hook. Now its an ENV var.
	export FINAL_IMAGE_FILE="${DESTIMG}/${version}.img"
	call_extension_method "post_build_image" << 'POST_BUILD_IMAGE'
*custom post build hook*
Called after the final .img file is built, before it is (possibly) written to an SD writer.
- *NOTE*: this hook used to take an argument ($1) for the final image produced.
  - Now it is passed as an environment variable `${FINAL_IMAGE_FILE}`
It is the last possible chance to modify `$CARD_DEVICE`.
POST_BUILD_IMAGE

	# move artefacts from temporally directory to its final destination
	[[ -n $compression_type ]] && rm $DESTIMG/${version}.img
	rsync -a --no-owner --no-group --remove-source-files $DESTIMG/${version}* ${FINALDEST}
	rm -rf --one-file-system $DESTIMG

	# write image to SD card
	if [[ $(lsblk "$CARD_DEVICE" 2> /dev/null) && -f ${FINALDEST}/${version}.img ]]; then

		# make sha256sum if it does not exists. we need it for comparisson
		if [[ -f "${FINALDEST}/${version}".img.sha ]]; then
			local ifsha=$(cat ${FINALDEST}/${version}.img.sha | awk '{print $1}')
		else
			local ifsha=$(sha256sum -b "${FINALDEST}/${version}".img | awk '{print $1}')
		fi

		display_alert "Writing image" "$CARD_DEVICE ${readsha}" "info"

		# write to SD card
		pv -p -b -r -c -N "$(logging_echo_prefix_for_pv "write_device") dd" ${FINALDEST}/${version}.img | dd of=$CARD_DEVICE bs=1M iflag=fullblock oflag=direct status=none

		call_extension_method "post_write_sdcard" <<- 'POST_BUILD_IMAGE'
			*run after writing img to sdcard*
			After the image is written to `$CARD_DEVICE`, but before verifying it.
			You can still set SKIP_VERIFY=yes to skip verification.
		POST_BUILD_IMAGE

		if [[ "${SKIP_VERIFY}" != "yes" ]]; then
			# read and compare
			display_alert "Verifying. Please wait!"
			local ofsha=$(dd if=$CARD_DEVICE count=$(du -b ${FINALDEST}/${version}.img | cut -f1) status=none iflag=count_bytes oflag=direct | sha256sum | awk '{print $1}')
			if [[ $ifsha == $ofsha ]]; then
				display_alert "Writing verified" "${version}.img" "info"
			else
				display_alert "Writing failed" "${version}.img" "err"
			fi
		fi
	elif [[ $(systemd-detect-virt) == 'docker' && -n $CARD_DEVICE ]]; then
		# display warning when we want to write sd card under Docker
		display_alert "Can't write to $CARD_DEVICE" "Enable docker privileged mode in config-docker.conf" "wrn"
	fi

} #############################################################################
