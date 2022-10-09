#!/usr/bin/env bash
# prepare_partitions
#
# creates image file, partitions and fs
# and mounts it to local dir
# FS-dependent stuff (boot and root fs partition types) happens here
#
# LOGGING: this is run under the log manager. so just redirect unwanted stderr to stdout, and it goes to log.
# this is under the logging manager. so just log to stdout (no redirections), and redirect stderr to stdout unless you want it on screen.
function prepare_partitions() {
	display_alert "Preparing image file for rootfs" "$BOARD $RELEASE" "info"

	# possible partition combinations
	# /boot: none, ext4, ext2, fat (BOOTFS_TYPE)
	# root: ext4, btrfs, f2fs, nfs (ROOTFS_TYPE)

	# declare makes local variables by default if used inside a function
	# NOTE: mountopts string should always start with comma if not empty

	# array copying in old bash versions is tricky, so having filesystems as arrays
	# with attributes as keys is not a good idea
	declare -A parttype mkopts mkopts_label mkfs mountopts

	parttype[ext4]=ext4
	parttype[ext2]=ext2
	parttype[fat]=fat16
	parttype[f2fs]=ext4 # not a copy-paste error
	parttype[btrfs]=btrfs
	parttype[xfs]=xfs
	# parttype[nfs] is empty

	# metadata_csum and 64bit may need to be disabled explicitly when migrating to newer supported host OS releases
	if [[ $HOSTRELEASE =~ buster|bullseye|bookworm|sid|focal|impish|hirsute|jammy|kinetic|lunar|ulyana|ulyssa|uma|una|vanessa|vera ]]; then
		mkopts[ext4]="-q -m 2 -O ^64bit,^metadata_csum"
	fi
	# mkopts[fat] is empty
	mkopts[ext2]=''
	# mkopts[f2fs] is empty
	mkopts[btrfs]='-m dup'
	# mkopts[xfs] is empty
	# mkopts[nfs] is empty

	mkopts_label[ext4]='-L '
	mkopts_label[ext2]='-L '
	mkopts_label[fat]='-n '
	mkopts_label[f2fs]='-l '
	mkopts_label[btrfs]='-L '
	mkopts_label[xfs]='-L '
	# mkopts_label[nfs] is empty

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
	UEFI_FS_LABEL="${UEFI_FS_LABEL:-armbi_efi}"
	ROOT_FS_LABEL="${ROOT_FS_LABEL:-armbi_root}"
	BOOT_FS_LABEL="${BOOT_FS_LABEL:-armbi_boot}"

	call_extension_method "pre_prepare_partitions" "prepare_partitions_custom" <<- 'PRE_PREPARE_PARTITIONS'
		*allow custom options for mkfs*
		Good time to change stuff like mkfs opts, types etc.
	PRE_PREPARE_PARTITIONS

	# stage: determine partition configuration
	local next=1
	# Check if we need UEFI partition
	if [[ $UEFISIZE -gt 0 ]]; then
		# Check if we need BIOS partition
		[[ $BIOSSIZE -gt 0 ]] && local biospart=$((next++))
		local uefipart=$((next++))
	fi
	# Check if we need boot partition
	if [[ -n $BOOTFS_TYPE || $ROOTFS_TYPE != ext4 || $CRYPTROOT_ENABLE == yes ]]; then
		local bootpart=$((next++))
		local bootfs=${BOOTFS_TYPE:-ext4}
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE}
	else
		BOOTSIZE=0
	fi
	# Check if we need root partition
	[[ $ROOTFS_TYPE != nfs ]] &&
		rootpart=$((next++))

	display_alert "calculated rootpart" "rootpart: ${rootpart}" "debug"

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
		# Hardcoded overhead +25% is needed for desktop images,
		# for CLI it could be lower. Align the size up to 4MiB
		if [[ $BUILD_DESKTOP == yes ]]; then
			local sdsize=$(bc -l <<< "scale=0; ((($imagesize * 1.35) / 1 + 0) / 4 + 1) * 4")
		else
			local sdsize=$(bc -l <<< "scale=0; ((($imagesize * 1.30) / 1 + 0) / 4 + 1) * 4")
		fi
	fi

	# stage: create blank image
	display_alert "Creating blank image for rootfs" "truncate: $sdsize MiB" "info"
	run_host_command_logged truncate --size=${sdsize}M ${SDCARD}.raw # please provide EVIDENCE of problems with this; using dd is very slow
	run_host_command_logged sync

	# stage: calculate boot partition size
	local bootstart=$(($OFFSET * 2048))
	local rootstart=$(($bootstart + ($BOOTSIZE * 2048) + ($UEFISIZE * 2048)))
	local bootend=$(($rootstart - 1))

	# stage: create partition table
	display_alert "Creating partitions" "${bootfs:+/boot: $bootfs }root: $ROOTFS_TYPE" "info"
	if [[ "${USE_HOOK_FOR_PARTITION}" == "yes" ]]; then
		{ [[ "$IMAGE_PARTITION_TABLE" == "msdos" ]] && echo "label: dos" || echo "label: $IMAGE_PARTITION_TABLE"; } |
			run_host_command_logged sfdisk ${SDCARD}.raw || exit_with_error "Create partition table fail"

		call_extension_method "create_partition_table" <<- 'CREATE_PARTITION_TABLE'
			*only called when USE_HOOK_FOR_PARTITION=yes to create the complete partition table*
			Finally, we can get our own partition table. You have to partition ${SDCARD}.raw
			yourself. Good luck.
		CREATE_PARTITION_TABLE
	else
		{
			[[ "$IMAGE_PARTITION_TABLE" == "msdos" ]] && echo "label: dos" || echo "label: $IMAGE_PARTITION_TABLE"

			local next=$OFFSET
			if [[ -n "$biospart" ]]; then
				# gpt: BIOS boot
				local type="21686148-6449-6E6F-744E-656564454649"
				echo "$biospart : name=\"bios\", start=${next}MiB, size=${BIOSSIZE}MiB, type=${type}"
				local next=$(($next + $BIOSSIZE))
			fi
			if [[ -n "$uefipart" ]]; then
				# dos: EFI (FAT-12/16/32)
				# gpt: EFI System
				[[ "$IMAGE_PARTITION_TABLE" != "gpt" ]] && local type="ef" || local type="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
				echo "$uefipart : name=\"efi\", start=${next}MiB, size=${UEFISIZE}MiB, type=${type}"
				local next=$(($next + $UEFISIZE))
			fi
			if [[ -n "$bootpart" ]]; then
				# Linux extended boot
				[[ "$IMAGE_PARTITION_TABLE" != "gpt" ]] && local type="ea" || local type="BC13C2FF-59E6-4262-A352-B275FD6F7172"
				if [[ -n "$rootpart" ]]; then
					echo "$bootpart : name=\"bootfs\", start=${next}MiB, size=${BOOTSIZE}MiB, type=${type}"
					local next=$(($next + $BOOTSIZE))
				else
					# no `size` argument mean "as much as possible"
					echo "$bootpart : name=\"bootfs\", start=${next}MiB, type=${type}"
				fi
			fi
			if [[ -n "$rootpart" ]]; then
				# dos: Linux
				# gpt: Linux filesystem
				[[ "$IMAGE_PARTITION_TABLE" != "gpt" ]] && local type="83" || local type="0FC63DAF-8483-4772-8E79-3D69D8477DE4"
				# no `size` argument mean "as much as possible"
				echo "$rootpart : name=\"rootfs\", start=${next}MiB, type=${type}"
			fi
		} |
			run_host_command_logged sfdisk ${SDCARD}.raw || exit_with_error "Partition fail."
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
	display_alert "Allocated loop device" "LOOP=${LOOP}"

	check_loop_device "$LOOP"

	run_host_command_logged losetup $LOOP ${SDCARD}.raw # @TODO: had a '-P- here, what was it?

	# loop device was grabbed here, unlock
	flock -u $FD

	display_alert "Running partprobe" "${LOOP}" "debug"
	run_host_command_logged partprobe $LOOP

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
		run_host_command_logged mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} ${mkopts_label[$ROOTFS_TYPE]:+${mkopts_label[$ROOTFS_TYPE]}"$ROOT_FS_LABEL"} "${rootdevice}"
		[[ $ROOTFS_TYPE == ext4 ]] && run_host_command_logged tune2fs -o journal_data_writeback "$rootdevice"
		if [[ $ROOTFS_TYPE == btrfs && $BTRFS_COMPRESSION != none ]]; then
			local fscreateopt="-o compress-force=${BTRFS_COMPRESSION}"
		fi
		sync # force writes to be really flushed
		display_alert "Mounting rootfs" "$rootdevice"
		run_host_command_logged mount ${fscreateopt} $rootdevice $MOUNT/
		# create fstab (and crypttab) entry
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			# map the LUKS container partition via its UUID to be the 'cryptroot' device
			echo "$ROOT_MAPPER UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart}) none luks" >> $SDCARD/etc/crypttab
			local rootfs=$rootdevice # used in fstab
		else
			local rootfs="UUID=$(blkid -s UUID -o value $rootdevice)"
		fi
		echo "$rootfs / ${mkfs[$ROOTFS_TYPE]} defaults,noatime${mountopts[$ROOTFS_TYPE]} 0 1" >> $SDCARD/etc/fstab
	else
		# update_initramfs will fail if /lib/modules/ doesn't exist
		mount --bind --make-private $SDCARD $MOUNT/
		echo "/dev/nfs / nfs defaults 0 0" >> $SDCARD/etc/fstab
	fi

	if [[ -n $bootpart ]]; then
		display_alert "Creating /boot" "$bootfs on ${LOOP}p${bootpart}"
		check_loop_device "${LOOP}p${bootpart}"
		run_host_command_logged mkfs.${mkfs[$bootfs]} ${mkopts[$bootfs]} ${mkopts_label[$bootfs]:+${mkopts_label[$bootfs]}"$BOOT_FS_LABEL"} ${LOOP}p${bootpart}
		mkdir -p $MOUNT/boot/
		run_host_command_logged mount ${LOOP}p${bootpart} $MOUNT/boot/
		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${bootpart}) /boot ${mkfs[$bootfs]} defaults${mountopts[$bootfs]} 0 2" >> $SDCARD/etc/fstab
	fi
	if [[ -n $uefipart ]]; then
		display_alert "Creating EFI partition" "FAT32 ${UEFI_MOUNT_POINT} on ${LOOP}p${uefipart} label ${UEFI_FS_LABEL}"
		check_loop_device "${LOOP}p${uefipart}"
		run_host_command_logged mkfs.fat -F32 -n "${UEFI_FS_LABEL^^}" ${LOOP}p${uefipart} 2>&1 # "^^" makes variable UPPERCASE, required for FAT32.
		mkdir -p "${MOUNT}${UEFI_MOUNT_POINT}"
		run_host_command_logged mount ${LOOP}p${uefipart} "${MOUNT}${UEFI_MOUNT_POINT}"
		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${uefipart}) ${UEFI_MOUNT_POINT} vfat defaults 0 2" >> $SDCARD/etc/fstab
	fi
	echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> $SDCARD/etc/fstab

	call_extension_method "format_partitions" <<- 'FORMAT_PARTITIONS'
		*if you created your own partitions, this would be a good time to format them*
		The loop device is mounted, so ${LOOP}p1 is it's first partition etc.
	FORMAT_PARTITIONS

	# stage: adjust boot script or boot environment
	if [[ -f $SDCARD/boot/armbianEnv.txt ]]; then
		display_alert "Found armbianEnv.txt" "${SDCARD}/boot/armbianEnv.txt" "debug"
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			echo "rootdev=$rootdevice cryptdevice=UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart}):$ROOT_MAPPER" >> "${SDCARD}/boot/armbianEnv.txt"
		else
			echo "rootdev=$rootfs" >> "${SDCARD}/boot/armbianEnv.txt"
		fi
		echo "rootfstype=$ROOTFS_TYPE" >> $SDCARD/boot/armbianEnv.txt
	elif [[ $rootpart != 1 ]] && [[ $SRC_EXTLINUX != yes ]]; then
		echo "rootfstype=$ROOTFS_TYPE" >> "${SDCARD}/boot/armbianEnv.txt"

		call_extension_method "image_specific_armbian_env_ready" <<- 'IMAGE_SPECIFIC_ARMBIAN_ENV_READY'
			*during image build, armbianEnv.txt is ready for image-specific customization (not in BSP)*
			You can write to `"${SDCARD}/boot/armbianEnv.txt"` here, it is guaranteed to exist.
		IMAGE_SPECIFIC_ARMBIAN_ENV_READY

	elif [[ $rootpart != 1 && $SRC_EXTLINUX != yes && -f "${SDCARD}/boot/${bootscript_dst}" ]]; then
		local bootscript_dst=${BOOTSCRIPT##*:}
		sed -i 's/mmcblk0p1/mmcblk0p2/' $SDCARD/boot/$bootscript_dst
		sed -i -e "s/rootfstype=ext4/rootfstype=$ROOTFS_TYPE/" \
			-e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $SDCARD/boot/$bootscript_dst
	fi

	# if we have boot.ini = remove armbianEnv.txt and add UUID there if enabled
	if [[ -f $SDCARD/boot/boot.ini ]]; then
		display_alert "Found boot.ini" "${SDCARD}/boot/boot.ini" "debug"
		sed -i -e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $SDCARD/boot/boot.ini
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			local rootpart="UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart})"
			sed -i 's/^setenv rootdev .*/setenv rootdev "\/dev\/mapper\/'$ROOT_MAPPER' cryptdevice='$rootpart':'$ROOT_MAPPER'"/' $SDCARD/boot/boot.ini
		else
			sed -i 's/^setenv rootdev .*/setenv rootdev "'$rootfs'"/' $SDCARD/boot/boot.ini
		fi
		if [[ $LINUXFAMILY != meson64 ]]; then # @TODO: why only for meson64?
			[[ -f $SDCARD/boot/armbianEnv.txt ]] && rm $SDCARD/boot/armbianEnv.txt
		fi
	fi

	# if we have a headless device, set console to DEFAULT_CONSOLE
	if [[ -n $DEFAULT_CONSOLE && -f $SDCARD/boot/armbianEnv.txt ]]; then
		if grep -lq "^console=" $SDCARD/boot/armbianEnv.txt; then
			sed -i "s/^console=.*/console=$DEFAULT_CONSOLE/" $SDCARD/boot/armbianEnv.txt
		else
			echo "console=$DEFAULT_CONSOLE" >> $SDCARD/boot/armbianEnv.txt
		fi
	fi

	# recompile .cmd to .scr if boot.cmd exists
	if [[ -f $SDCARD/boot/boot.cmd ]]; then
		if [ -z $BOOTSCRIPT_OUTPUT ]; then
			BOOTSCRIPT_OUTPUT=boot.scr
		fi
		run_host_command_logged mkimage -C none -A arm -T script -d $SDCARD/boot/boot.cmd $SDCARD/boot/${BOOTSCRIPT_OUTPUT}
	fi

	# complement extlinux config if it exists; remove armbianEnv in this case.
	if [[ -f $SDCARD/boot/extlinux/extlinux.conf ]]; then
		echo "  append root=$rootfs $SRC_CMDLINE $MAIN_CMDLINE" >> $SDCARD/boot/extlinux/extlinux.conf
		display_alert "extlinux.conf exists" "removing armbianEnv.txt" "warn"
		[[ -f $SDCARD/boot/armbianEnv.txt ]] && run_host_command_logged rm -v $SDCARD/boot/armbianEnv.txt
	fi

	return 0 # there is a shortcircuit above! very tricky btw!
}
