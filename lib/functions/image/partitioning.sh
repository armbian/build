# prepare_partitions
#
# creates image file, partitions and fs
# and mounts it to local dir
# FS-dependent stuff (boot and root fs partition types) happens here
#
# LOGGING: this is run under the log manager. so just redirect unwanted stderr to stdout, and it goes to log.
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
	UEFI_FS_LABEL="${UEFI_FS_LABEL:-ARMBIEFI}" # Should be always uppercase

	call_extension_method "pre_prepare_partitions" "prepare_partitions_custom" <<- 'PRE_PREPARE_PARTITIONS'
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

	call_extension_method "prepare_image_size" "config_prepare_image_size" <<- 'PREPARE_IMAGE_SIZE'
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
				sgdisk --transpose 1:14 ${SDCARD}.raw
				sgdisk --transpose 2:15 ${SDCARD}.raw
				sgdisk --transpose 3:1 ${SDCARD}.raw
				# set the ESP (efi) flag on 15
				parted -s ${SDCARD}.raw -- set 14 bios_grub on
				parted -s ${SDCARD}.raw -- set 15 esp on
			else
				display_alert "Creating partitions" "UEFI+rootfs (no BIOS)" "info"
				# Simple EFI + root partition on GPT, no BIOS.
				parted -s ${SDCARD}.raw -- mkpart efi fat32 ${bootstart}s ${bootend}s
				parted -s ${SDCARD}.raw -- mkpart rootfs ${parttype[$ROOTFS_TYPE]} ${rootstart}s "100%"
				# transpose so EFI is in sda15 and root in sda1; requires sgdisk, parted cant do numbers
				sgdisk --transpose 1:15 ${SDCARD}.raw
				sgdisk --transpose 2:1 ${SDCARD}.raw
				# set the ESP (efi) flag on 15
				parted -s ${SDCARD}.raw -- set 15 esp on
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

	export LOOP
	LOOP=$(losetup -f) || exit_with_error "Unable to find free loop device"
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
		mkfs.fat -F32 -n "${UEFI_FS_LABEL^^}" ${LOOP}p${uefipart} 2>&1 # "^^" makes variable UPPERCASE, required for FAT32.
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
		echo "  append root=$rootfs $SRC_CMDLINE $MAIN_CMDLINE" >> $SDCARD/boot/extlinux/extlinux.conf
		[[ -f $SDCARD/boot/armbianEnv.txt ]] && rm $SDCARD/boot/armbianEnv.txt
	fi

}
