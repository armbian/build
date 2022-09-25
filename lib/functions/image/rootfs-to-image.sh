# create_image
#
# finishes creation of image from cached rootfs
#
create_image_from_sdcard_rootfs() {
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
		display_alert "Copying files via rsync to" "/ at ${MOUNT}"
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
	display_alert "Copying files to" "/boot at ${MOUNT}"
	if [[ $(findmnt --target $MOUNT/boot -o FSTYPE -n) == vfat ]]; then
		# fat32
		run_host_command_logged rsync -rLtWh --info=progress0,stats1 "$SDCARD/boot" "$MOUNT"
	else
		# ext4
		run_host_command_logged rsync -aHWXh --info=progress0,stats1 "$SDCARD/boot" "$MOUNT"
	fi

	call_extension_method "pre_update_initramfs" "config_pre_update_initramfs" <<- 'PRE_UPDATE_INITRAMFS'
		*allow config to hack into the initramfs create process*
		Called after rsync has synced both `/root` and `/root` on the target, but before calling `update_initramfs`.
	PRE_UPDATE_INITRAMFS

	# stage: create final initramfs
	[[ -n $KERNELSOURCE ]] && {
		update_initramfs "$MOUNT"
	}

	# DEBUG: print free space
	local freespace
	freespace=$(LC_ALL=C df -h)
	display_alert "Free SD cache" "$(echo "$freespace" | grep "${SDCARD}" | awk '{print $5}')" "info"
	display_alert "Mount point" "$(echo "$freespace" | grep "${MOUNT}" | head -1 | awk '{print $5}')" "info"

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

	# Check the partition table after the uboot code has been written
	display_alert "Partition table after write_uboot" "$LOOP" "debug"
	run_host_command_logged sfdisk -l "${LOOP}" # @TODO: use asset..

	run_host_command_logged sync

	umount_chroot_recursive "${MOUNT}"
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose $ROOT_MAPPER

	call_extension_method "post_umount_final_image" "config_post_umount_final_image" <<- 'POST_UMOUNT_FINAL_IMAGE'
		*allow config to hack into the image after the unmount*
		Called after unmounting both `/root` and `/boot`.
	POST_UMOUNT_FINAL_IMAGE

	display_alert "Freeing loop device" "${LOOP}"
	losetup -d "${LOOP}"
	unset LOOP # unset so cleanup handler does not try it again

	# We're done with ${MOUNT} by now, remove it.
	rm -rf --one-file-system "${MOUNT}"
	unset MOUNT

	mkdir -p "${DESTIMG}"
	# @TODO: misterious cwd, who sets it?

	mv "${SDCARD}.raw" "${DESTIMG}/${version}.img"

	# custom post_build_image_modify hook to run before fingerprinting and compression
	[[ $(type -t post_build_image_modify) == function ]] && display_alert "Custom Hook Detected" "post_build_image_modify" "info" && post_build_image_modify "${DESTIMG}/${version}.img"

	image_compress_and_checksum

	display_alert "Done building" "${FINALDEST}/${version}.img" "info" # A bit predicting the future, since it's still in DESTIMG at this point.

	# Previously, post_build_image passed the .img path as an argument to the hook. Now its an ENV var.
	export FINAL_IMAGE_FILE="${DESTIMG}/${version}.img"
	call_extension_method "post_build_image" <<- 'POST_BUILD_IMAGE'
		*custom post build hook*
		Called after the final .img file is built, before it is (possibly) written to an SD writer.
		- *NOTE*: this hook used to take an argument ($1) for the final image produced.
		  - Now it is passed as an environment variable `${FINAL_IMAGE_FILE}`
		It is the last possible chance to modify `$CARD_DEVICE`.
	POST_BUILD_IMAGE

	display_alert "Moving artefacts from temporary directory to its final destination" "${version}" "debug"
	[[ -n $compression_type ]] && run_host_command_logged rm -v "${DESTIMG}/${version}.img"
	run_host_command_logged rsync -av --no-owner --no-group --remove-source-files "${DESTIMG}/${version}"* "${FINALDEST}"
	run_host_command_logged rm -rfv --one-file-system "${DESTIMG}"

	# write image to SD card
	write_image_to_device "${FINALDEST}/${version}.img" "${CARD_DEVICE}"

}

function trap_handler_cleanup_destimg() {
	[[ ! -d "${DESTIMG}" ]] && return 0
	display_alert "Cleaning up temporary DESTIMG" "${DESTIMG}" "debug"
	rm -rf --one-file-system "${DESTIMG}"
}
