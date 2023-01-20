#!/usr/bin/env bash
# create_image
#
# finishes creation of image from cached rootfs
#
function create_image_from_sdcard_rootfs() {
	# create DESTIMG, hooks might put stuff there early.
	mkdir -p "${DESTIMG}"

	# add a cleanup trap hook do make sure we don't leak it if stuff fails
	add_cleanup_handler trap_handler_cleanup_destimg

	# stage: create file name
	# @TODO: rpardini: determine the image file name produced. a bit late in the game, since it uses VER which is from the kernel package.
	local version="${VENDOR}_${REVISION}_${BOARD^}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}${DESKTOP_ENVIRONMENT:+_$DESKTOP_ENVIRONMENT}"
	[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
	[[ $BUILD_MINIMAL == yes ]] && version=${version}_minimal
	[[ $ROOTFS_TYPE == nfs ]] && version=${version}_nfsboot

	if [[ $ROOTFS_TYPE != nfs ]]; then
		display_alert "Copying files via rsync to" "/ (MOUNT root)"
		run_host_command_logged rsync -aHWXh \
			--exclude="/boot/*" \
			--exclude="/dev/*" \
			--exclude="/proc/*" \
			--exclude="/run/*" \
			--exclude="/tmp/*" \
			--exclude="/sys/*" \
			--info=progress0,stats1 $SDCARD/ $MOUNT/
	else
		display_alert "Creating rootfs archive" "rootfs.tgz" "info"
		tar cp --xattrs --directory=$SDCARD/ --exclude='./boot/*' --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . |
			pv -p -b -r -s "$(du -sb "$SDCARD"/ | cut -f1)" \
				-N "$(logging_echo_prefix_for_pv "create_rootfs_archive") rootfs.tgz" |
			gzip -c > "$DEST/images/${version}-rootfs.tgz"
	fi

	# stage: rsync /boot
	display_alert "Copying files to" "/boot (MOUNT /boot)"
	if [[ $(findmnt --noheadings --output FSTYPE --target "$MOUNT/boot" --uniq) == vfat ]]; then
		run_host_command_logged rsync -rLtWh --info=progress0,stats1 "$SDCARD/boot" "$MOUNT" # fat32
	else
		run_host_command_logged rsync -aHWXh --info=progress0,stats1 "$SDCARD/boot" "$MOUNT" # ext4
	fi

	call_extension_method "pre_update_initramfs" "config_pre_update_initramfs" <<- 'PRE_UPDATE_INITRAMFS'
		*allow config to hack into the initramfs create process*
		Called after rsync has synced both `/root` and `/root` on the target, but before calling `update_initramfs`.
	PRE_UPDATE_INITRAMFS

	# stage: create final initramfs
	[[ -n $KERNELSOURCE ]] && {
		update_initramfs "$MOUNT"
	}

	# DEBUG: print free space @TODO this needs work, grepping might not be ideal here
	local freespace
	freespace=$(LC_ALL=C df -h || true) # don't break on failures
	display_alert "Free SD cache" "$(echo -e "$freespace" | awk -v mp="${SDCARD}" '$6==mp {print $5}')" "info"
	display_alert "Mount point" "$(echo -e "$freespace" | awk -v mp="${MOUNT}" '$6==mp {print $5}')" "info"

	# stage: write u-boot, unless the deb is not there, which would happen if BOOTCONFIG=none
	# exception: if we use the one from repository, install version which was downloaded from repo
	if [[ -f "${DEB_STORAGE}"/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb ]] || [[ -n $UBOOT_REPO_VERSION ]]; then
		write_uboot_to_loop_image "${LOOP}"
	fi

	# fix wrong / permissions
	chmod 755 "${MOUNT}"

	call_extension_method "pre_umount_final_image" "config_pre_umount_final_image" <<- 'PRE_UMOUNT_FINAL_IMAGE'
		*allow config to hack into the image before the unmount*
		Called before unmounting both `/root` and `/boot`.
	PRE_UMOUNT_FINAL_IMAGE

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		# Check the partition table after the uboot code has been written
		display_alert "Partition table after write_uboot" "$LOOP" "debug"
		run_host_command_logged sfdisk -l "${LOOP}" # @TODO: use asset..
	fi

	wait_for_disk_sync "before umount MOUNT"

	umount_chroot_recursive "${MOUNT}" "MOUNT"
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose "$ROOT_MAPPER"

	call_extension_method "post_umount_final_image" "config_post_umount_final_image" <<- 'POST_UMOUNT_FINAL_IMAGE'
		*allow config to hack into the image after the unmount*
		Called after unmounting both `/root` and `/boot`.
	POST_UMOUNT_FINAL_IMAGE

	free_loop_device_insistent "${LOOP}"
	unset LOOP # unset so cleanup handler does not try it again

	# We're done with ${MOUNT} by now, remove it.
	rm -rf --one-file-system "${MOUNT}"
	# unset MOUNT # don't unset, it's readonly now

	mkdir -p "${DESTIMG}"
	# @TODO: misterious cwd, who sets it?

	run_host_command_logged mv -v "${SDCARD}.raw" "${DESTIMG}/${version}.img"

	# custom post_build_image_modify hook to run before fingerprinting and compression
	[[ $(type -t post_build_image_modify) == function ]] && display_alert "Custom Hook Detected" "post_build_image_modify" "info" && post_build_image_modify "${DESTIMG}/${version}.img"

	declare compression_type # set by image_compress_and_checksum
	image_compress_and_checksum

	# Previously, post_build_image passed the .img path as an argument to the hook. Now its an ENV var.
	export FINAL_IMAGE_FILE="${DESTIMG}/${version}.img"
	call_extension_method "post_build_image" <<- 'POST_BUILD_IMAGE'
		*custom post build hook*
		Called after the final .img file is built, before it is (possibly) written to an SD writer.
		- *NOTE*: this hook used to take an argument ($1) for the final image produced.
		  - Now it is passed as an environment variable `${FINAL_IMAGE_FILE}`
		It is the last possible chance to modify `$CARD_DEVICE`.
	POST_BUILD_IMAGE

	# If we compressed the image, get rid of the original, and leave only the compressed one.
	[[ -n $compression_type ]] && rm -f "${DESTIMG}/${version}.img"
	if [[ -n $compression_type ]]; then
		run_host_command_logged rm -v "${DESTIMG}/${version}.img"
	fi

	# Move all files matching the prefix from source to dest. Custom hooks might generate more than one img.
	declare source_dir="${DESTIMG}"
	declare destination_dir="${FINALDEST}"
	declare source_files_prefix="${version}"
	move_images_to_final_destination

	display_alert "Done building" "${FINALDEST}/${version}.img" "info" # A bit predicting the future, since it's still in DESTIMG at this point.

	# write image to SD card
	write_image_to_device "${FINALDEST}/${version}.img" "${CARD_DEVICE}"

	return 0
}

function move_images_to_final_destination() {
	# validate that source_dir and destination_dir exist
	[[ ! -d "${source_dir}" ]] && return 1
	[[ ! -d "${destination_dir}" ]] && return 2

	declare -a source_files=("${source_dir}/${source_files_prefix}."*)
	if [[ ${#source_files[@]} -eq 0 ]]; then
		display_alert "No files to deploy" "${source_dir}/${source_files_prefix}.*" "wrn"
	fi

	# if source_dir and destination_dir are on the same filesystem. use stat to get the device number
	declare source_dir_device
	declare destination_dir_device
	source_dir_device=$(stat -c %d "${source_dir}")
	destination_dir_device=$(stat -c %d "${destination_dir}")
	display_alert "source_dir_device/destination_dir_device" "${source_dir_device}/${destination_dir_device}" "debug"
	if [[ "${source_dir_device}" == "${destination_dir_device}" ]]; then
		# loop over source_files, display the size of each file, and move it
		for source_file in "${source_files[@]}"; do
			declare base_name_source="${source_file##*/}" source_size_human=""
			source_size_human=$(stat -c %s "${source_file}" | numfmt --to=iec-i --suffix=B --format="%.2f")
			display_alert "Fast-moving file to output/images" "-> ${base_name_source} (${source_size_human})" "info"
			run_host_command_logged mv "${source_file}" "${destination_dir}"
		done
	else
		display_alert "Moving artefacts using rsync to final destination" "${version}" "info"
		run_host_command_logged rsync -av --no-owner --no-group --remove-source-files "${DESTIMG}/${version}"* "${FINALDEST}"
		run_host_command_logged rm -rfv --one-file-system "${DESTIMG}"
	fi
	return 0
}

function trap_handler_cleanup_destimg() {
	[[ ! -d "${DESTIMG}" ]] && return 0
	display_alert "Cleaning up temporary DESTIMG" "${DESTIMG}" "debug"
	rm -rf --one-file-system "${DESTIMG}"
}
