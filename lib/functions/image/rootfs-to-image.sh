#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function calculate_image_version() {
	declare kernel_version_for_image="unknown"
	kernel_version_for_image="${IMAGE_INSTALLED_KERNEL_VERSION/-$LINUXFAMILY/}"

	declare vendor_version_prelude="${VENDOR}_${IMAGE_VERSION:-"${REVISION}"}_"
	if [[ "${include_vendor_version:-"yes"}" == "no" ]]; then
		vendor_version_prelude=""
	fi

	calculated_image_version="${vendor_version_prelude}${BOARD^}_${RELEASE}_${BRANCH}_${kernel_version_for_image}${DESKTOP_ENVIRONMENT:+_$DESKTOP_ENVIRONMENT}${EXTRA_IMAGE_SUFFIX}"
	[[ $BUILD_DESKTOP == yes ]] && calculated_image_version=${calculated_image_version}_desktop
	[[ $BUILD_MINIMAL == yes ]] && calculated_image_version=${calculated_image_version}_minimal
	[[ $ROOTFS_TYPE == nfs ]] && calculated_image_version=${calculated_image_version}_nfsboot
	[[ $ROOTFS_TYPE == nfs-root ]] && calculated_image_version=${calculated_image_version}_nfsroot
	display_alert "Calculated image version" "${calculated_image_version}" "debug"
}

function create_image_from_sdcard_rootfs() {
	# create DESTIMG, hooks might put stuff there early.
	mkdir -p "${DESTIMG}"

	# add a cleanup trap hook do make sure we don't leak it if stuff fails
	add_cleanup_handler trap_handler_cleanup_destimg

	# calculate image filename, and store it in readonly global variable "version", for legacy reasons.
	declare calculated_image_version="undetermined"
	calculate_image_version
	declare -r -g version="${calculated_image_version}" # global readonly from here
	declare rsync_ea=" -X "
	declare exclude_home="--exclude=\"/home/*\""
	# Some usecase requires home directory to be included
	if [[ ${INCLUDE_HOME_DIR:-no} == yes ]]; then exclude_home=""; fi
	# nilfs2 fs does not have extended attributes support, and have to be ignored on copy
	if [[ $ROOTFS_TYPE == nilfs2 ]]; then rsync_ea=""; fi
	if [[ $ROOTFS_TYPE != nfs && $ROOTFS_TYPE != nfs-root ]]; then
		display_alert "Copying files via rsync to" "/ (MOUNT root)"
		run_host_command_logged rsync -aHWh $rsync_ea \
			--exclude="/boot" \
			--exclude="/dev/*" \
			--exclude="/proc/*" \
			--exclude="/run/*" \
			--exclude="/tmp/*" \
			--exclude="/sys/*" \
			$exclude_home \
			--info=progress0,stats1 $SDCARD/ $MOUNT/
	fi

	# stage: rsync /boot
	display_alert "Copying files to" "/boot (MOUNT /boot)"
	if [[ $(findmnt --noheadings --output FSTYPE --target "$MOUNT/boot" --uniq) == vfat ]]; then
		# FAT filesystems can't have symlinks; rsync, below, will replace them with copies (-L)...
		# ... unless they're dangling symlinks, in which case rsync will fail.
		# Find dangling symlinks in "$MOUNT/boot", warn, and remove them.
		display_alert "Checking for dangling symlinks" "in FAT32 /boot" "info"
		declare -a dangling_symlinks=()
		while IFS= read -r -d '' symlink; do
			dangling_symlinks+=("$symlink")
		done < <(find "$SDCARD/boot" -xtype l -print0)
		if [[ ${#dangling_symlinks[@]} -gt 0 ]]; then
			display_alert "Dangling symlinks in /boot" "$(printf '%s ' "${dangling_symlinks[@]}")" "warning"
			run_host_command_logged rm -fv "${dangling_symlinks[@]}"
		fi
		run_host_command_logged rsync -rLtWh --info=progress0,stats1 "$SDCARD/boot" "$MOUNT" # fat32
	else
		run_host_command_logged rsync -aHWXh --info=progress0,stats1 "$SDCARD/boot" "$MOUNT" # ext4
	fi

	call_extension_method "pre_update_initramfs" "config_pre_update_initramfs" <<- 'PRE_UPDATE_INITRAMFS'
		*allow config to hack into the initramfs create process*
		Called after rsync has synced both `/root` and `/root` on the target, but before calling `update_initramfs`.
	PRE_UPDATE_INITRAMFS

	# stage: create final initramfs
	[[ "${KERNELSOURCE}" != 'none' ]] && {
		update_initramfs "$MOUNT"
	}

	# DEBUG: print free space @TODO this needs work, grepping might not be ideal here
	local freespace
	freespace=$(LC_ALL=C df -h || true) # don't break on failures
	display_alert "Free SD cache" "$(echo -e "$freespace" | awk -v mp="${SDCARD}" '$6==mp {print $5}')" "info"
	display_alert "Mount point" "$(echo -e "$freespace" | awk -v mp="${MOUNT}" '$6==mp {print $5}')" "info"

	# stage: write u-boot, unless BOOTCONFIG=none
	declare -g -A image_artifacts_debs_reversioned
	if [[ "${BOOTCONFIG}" != "none" ]]; then
		write_uboot_to_loop_image "${LOOP}" "${DEB_STORAGE}/${image_artifacts_debs_reversioned["uboot"]}"
	fi

	# fix wrong / permissions
	chmod 755 "${MOUNT}"

	call_extension_method "pre_umount_final_image" "config_pre_umount_final_image" <<- 'PRE_UMOUNT_FINAL_IMAGE'
		*allow config to hack into the image before the unmount*
		Called before unmounting both `/root` and `/boot`.
	PRE_UMOUNT_FINAL_IMAGE

	if [[ $ROOTFS_TYPE == nfs || $ROOTFS_TYPE == nfs-root ]]; then
		# ROOTFS_COMPRESSION: zstd (default, .tar.zst) | gzip (.tar.gz) | none (skip archive)
		declare rootfs_compression="${ROOTFS_COMPRESSION:-zstd}"
		declare archive_ext="" archive_filter=""
		case "${rootfs_compression}" in
			gzip)
				archive_ext="tar.gz"
				archive_filter="gzip -c"
				;;
			zstd | zst)
				archive_ext="tar.zst"
				archive_filter="zstd -T0 -c"
				;;
			none) ;;
			*) exit_with_error "Unknown ROOTFS_COMPRESSION: '${rootfs_compression}' (expected: gzip|zstd|none)" ;;
		esac
		if [[ "${rootfs_compression}" == "none" && -z "${ROOTFS_EXPORT_DIR}" ]]; then
			exit_with_error "ROOTFS_COMPRESSION=none requires ROOTFS_EXPORT_DIR (otherwise nothing is produced)"
		fi

		declare -g ROOTFS_ARCHIVE_PATH=""
		if [[ "${rootfs_compression}" != "none" ]]; then
			ROOTFS_ARCHIVE_PATH="${FINALDEST}/${version}-rootfs.${archive_ext}"
			# Write to a hidden temp file in FINALDEST and rename in place on success —
			# keeps the publish atomic even when DESTIMG and FINALDEST are on different
			# filesystems. A failed tar/pv/compressor stage leaves only the hidden tmp,
			# never a truncated ${version}-rootfs.${archive_ext} that looks valid.
			run_host_command_logged mkdir -pv "${FINALDEST}"
			declare rootfs_archive_tmp="${FINALDEST}/.${version}-rootfs.${archive_ext}.tmp"
			display_alert "Creating rootfs archive" "${version}-rootfs.${archive_ext}" "info"
			# Subshell with pipefail so failures in tar/pv propagate (otherwise the
			# exit code of the final compressor stage hides truncation mid-archive).
			declare -a tar_excludes=(--exclude='./boot/*' --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' --exclude='./sys/*')
			[[ "${INCLUDE_HOME_DIR:-no}" != "yes" ]] && tar_excludes+=(--exclude='./home/*')
			rm -f "${rootfs_archive_tmp}"
			(
				set -o pipefail
				tar cp --xattrs --directory="$SDCARD/" "${tar_excludes[@]}" . |
					pv -p -b -r -s "$(du -sb "$SDCARD"/ | cut -f1)" \
						-N "$(logging_echo_prefix_for_pv "create_rootfs_archive") rootfs.${archive_ext}" |
					${archive_filter} > "${rootfs_archive_tmp}"
			)
			run_host_command_logged mv -v "${rootfs_archive_tmp}" "${ROOTFS_ARCHIVE_PATH}"
		fi

		# ROOTFS_EXPORT_DIR: when set, also rsync rootfs tree into this directory.
		# Useful when the build host is the NFS server, or has the NFS export mounted,
		# so netboot deployment is a single build step with no unpack/transport phase.
		if [[ -n "${ROOTFS_EXPORT_DIR}" ]]; then
			# Hard guard: the netboot extension confines the path to ${SRC}/output/
			# netboot-export/ when active, but plain ROOTFS_TYPE=nfs reaches this block
			# with the raw user value. A typo like / or ${SDCARD} would turn the
			# rsync --delete below into a destructive wipe.
			declare _export_resolved _sdcard_resolved
			_export_resolved="$(realpath -m "${ROOTFS_EXPORT_DIR}")"
			_sdcard_resolved="$(realpath -m "${SDCARD}")"
			if [[ -z "${_export_resolved}" || "${_export_resolved}" == "/" || "${_export_resolved}" == "${_sdcard_resolved}" ]]; then
				exit_with_error "Refusing rsync --delete to unsafe ROOTFS_EXPORT_DIR" "${ROOTFS_EXPORT_DIR}"
			fi
			display_alert "Exporting rootfs tree" "${ROOTFS_EXPORT_DIR}" "info"
			run_host_command_logged mkdir -pv "${ROOTFS_EXPORT_DIR}"
			# --delete so files removed from the source rootfs don't survive in a
			# reused export tree (otherwise the NFS root silently drifts from the image).
			# --delete-excluded additionally purges receiver-side files that match our
			# excludes (e.g. stale /home/* left over from a prior INCLUDE_HOME_DIR=yes build).
			run_host_command_logged rsync -aHWh --delete --delete-excluded $rsync_ea \
				--exclude="/boot/*" \
				--exclude="/dev/*" \
				--exclude="/proc/*" \
				--exclude="/run/*" \
				--exclude="/tmp/*" \
				--exclude="/sys/*" \
				$exclude_home \
				--info=progress0,stats1 "$SDCARD/" "${ROOTFS_EXPORT_DIR}/"
		fi
	fi

	call_extension_method "post_create_rootfs_archive" <<- 'POST_CREATE_ROOTFS_ARCHIVE'
		*called after the rootfs archive / export tree is produced*
		Runs after pre_umount_final_image and after the archive step, so any
		path the archive step sets (e.g. ROOTFS_ARCHIVE_PATH) is populated.
		Use this instead of pre_umount_final_image when you need the final
		archive path — deploy hooks that ship the archive belong here.
	POST_CREATE_ROOTFS_ARCHIVE

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		# Check the partition table after the uboot code has been written
		display_alert "Partition table after write_uboot" "$LOOP" "debug"
		run_host_command_logged sfdisk -l "${LOOP}" # @TODO: use asset..
	fi

	wait_for_disk_sync "before umount MOUNT"

	umount_chroot_recursive "${MOUNT}" "MOUNT"

	call_extension_method "post_umount_final_image" "config_post_umount_final_image" <<- 'POST_UMOUNT_FINAL_IMAGE'
		*allow config to hack into the image after the unmount*
		Called after unmounting both `/root` and `/boot`.
	POST_UMOUNT_FINAL_IMAGE

	free_loop_device_insistent "${LOOP}"
	unset LOOP # unset so cleanup handler does not try it again

	# We're done with ${MOUNT} by now, remove it.
	rm -rf --one-file-system "${MOUNT}"
	# unset MOUNT # don't unset, it's readonly now

	# nfs-root: no local storage image. Kernel/DTB/initrd are already staged for TFTP
	# by the netboot extension (pre_umount_final_image hook). Rootfs lands in the
	# archive under ${FINALDEST} (when ROOTFS_COMPRESSION != none) and/or in the
	# user-selected ${ROOTFS_EXPORT_DIR}, which may live outside ${FINALDEST}.
	# Drop SDCARD.raw and skip the .img pipeline (write-to-SD, fingerprint, compress).
	if [[ "${ROOTFS_TYPE}" == "nfs-root" ]]; then
		display_alert "nfs-root" "no local storage image produced" "info"
		rm -f "${SDCARD}.raw"
		return 0
	fi

	mkdir -p "${DESTIMG}"
	# @TODO: misterious cwd, who sets it?

	run_host_command_logged mv -v "${SDCARD}.raw" "${DESTIMG}/${version}.img"

	# custom post_build_image_modify hook to run before fingerprinting and compression
	[[ $(type -t post_build_image_modify) == function ]] && display_alert "Custom Hook Detected" "post_build_image_modify" "info" && post_build_image_modify "${DESTIMG}/${version}.img"

	# Previously, post_build_image passed the .img path as an argument to the hook. Now its an ENV var.
	declare -g FINAL_IMAGE_FILE="${DESTIMG}/${version}.img"
	call_extension_method "post_build_image" <<- 'POST_BUILD_IMAGE'
		*custom post build hook*
		Called after the final .img file is built, before it is (possibly) written to an SD writer.
		- *NOTE*: this hook used to take an argument ($1) for the final image produced.
		  - Now it is passed as an environment variable `${FINAL_IMAGE_FILE}`
		It is the last possible chance to modify `$CARD_DEVICE`.
	POST_BUILD_IMAGE

	# Before compressing or moving, write it to SD card if such was requested and image was produced.
	if [[ -f "${DESTIMG}/${version}.img" ]]; then
		display_alert "Done building" "${version}.img" "info"
		fingerprint_image "${DESTIMG}/${version}.img.txt" "${version}"

		write_image_to_device_and_run_hooks "${DESTIMG}/${version}.img"
	fi

	declare compression_type                                    # set by image_compress_and_checksum
	output_images_compress_and_checksum "${DESTIMG}/${version}" # this compressed on-disk, and removes the originals.

	# Move all files matching the prefix from source to dest. Custom hooks might generate more than one img.
	declare source_dir="${DESTIMG}"
	declare destination_dir="${FINALDEST}"
	declare source_files_prefix="${version}"
	move_images_to_final_destination

	return 0
}

function write_image_to_device_and_run_hooks() {
	if [[ ! -f "${1}" ]]; then
		exit_with_error "Image file not found '${1}'"
	fi
	declare built_image_file="${1}"

	# write image to SD card
	write_image_to_device "${built_image_file}" "${CARD_DEVICE}"

	# Hook: post_build_image_write
	call_extension_method "post_build_image_write" <<- 'POST_BUILD_IMAGE_WRITE'
		*custom post build hook*
		Called after the final .img file is ready, and possibly written to an SD card.
		The full path to the image is available in `${built_image_file}`.
	POST_BUILD_IMAGE_WRITE

	unset built_image_file
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
