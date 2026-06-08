#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2024 Rafel del Valle <rvalle@privaz.io>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# This extension will place the root partition on an LVM volume.
# It is possible to customise the volume group name and the image is extended to allow
# for LVM headers

# In case of failed builds check for leaked logical volumes with "dmsetup list" and
# remove them with "dmsetup remove"

# Additional log infomration will be created on lvm.log

# We will need to create several LVM objects: PV VG VOL on the image from the host
function add_host_dependencies__lvm_host_deps() {
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} lvm2"
}

function extension_prepare_config__lvm_image_suffix() {
	# Add to image suffix.
	EXTRA_IMAGE_SUFFIXES+=("-lvm")
}

function extension_prepare_config__prepare_lvm() {
	# Config for lvm, boot partition is required, many bootloaders do not support LVM.
	declare -g BOOTPART_REQUIRED=yes
	declare -g LVM_VG_NAME="${LVM_VG_NAME:-armbivg}"
	declare -g EXTRA_ROOTFS_MIB_SIZE=256
	add_packages_to_image lvm2
}

function post_create_partitions__setup_lvm() {
	# Setup LVM on the partition, ROOTFS
	parted -s "${SDCARD}.raw" -- set "${rootpart}" lvm on
	display_alert "LVM Partition table created" "${EXTENSION}" "info"
	parted -s "${SDCARD}.raw" -- print >> "${DEST}/${LOG_SUBPATH}/lvm.log" 2>&1
}

function prepare_root_device__create_volume_group() {

	# the partition to setup LVM on is defined as rootpart
	display_alert "LVM will be on ${rootdevice}" "${EXTENSION}" "info"

	# Calculate the required volume size
	declare -g -i rootfs_size
	rootfs_size=$(du --apparent-size -sm "${SDCARD}"/ | cut -f1) # MiB
	display_alert "Current rootfs size" "$rootfs_size MiB" "info"
	volsize=$(bc -l <<< "scale=0; ((($rootfs_size * 1.30) / 1 + 0) / 4 + 1) * 4")
	display_alert "Root volume size" "$volsize MiB" "info"

	# Create the PV VG and VOL
	display_alert "LVM Creating VG" "${rootdevice}" "info"
	check_loop_device "${rootdevice}"
	pvcreate "${rootdevice}"
	wait_for_disk_sync "wait for pvcreate to sync"
	vgcreate "${LVM_VG_NAME}" "${rootdevice}"
	add_cleanup_handler cleanup_lvm
	wait_for_disk_sync "wait for vgcreate to sync"
	# Note that devices wont come up automatically inside docker
	lvcreate -Zn --name root --size "${volsize}M" "${LVM_VG_NAME}"
	vgmknodes
	lvs >> "${DEST}/${LOG_SUBPATH}/lvm.log" 2>&1

	rootdevice="/dev/mapper/${LVM_VG_NAME}-root"
	display_alert "LVM created volume group - root device ${rootdevice}" "${EXTENSION}" "info"
}

function label_partition() {
	local rootdevice="/dev/mapper/${LVM_VG_NAME}-root"
	# btrfs and xfs relabel via the mount point; resolve it structurally
	# (findmnt is a single util-linux call, robust to spaces and to multiple
	# mounts of the same device) instead of parsing mount(8) output.
	local mountpoint
	mountpoint="$(findmnt --noheadings --first-only --output TARGET --source "${rootdevice}")"

	case "${ROOTFS_TYPE}" in
		ext4 | ext2)
			e2label "${rootdevice}" "${ROOT_FS_LABEL}"
			;;
		btrfs)
			btrfs filesystem label "${mountpoint}" "${ROOT_FS_LABEL}"
			;;
		nilfs2)
			nilfs-tune -L "${ROOT_FS_LABEL}" "${rootdevice}"
			;;
		xfs)
			xfs_io -c "label -s ${ROOT_FS_LABEL}" "${mountpoint}"
			;;
	esac
}

function format_partitions__format_lvm() {
	# Only these filesystems support relabeling the mounted root here; skip the rest.
	case "${ROOTFS_TYPE}" in
		ext4 | ext2 | btrfs | nilfs2 | xfs) ;;
		*)
			display_alert "LVM partition labels skipped" "${EXTENSION} - unsupported ${ROOTFS_TYPE}" "info"
			return
			;;
	esac

	# Label the root volume
	if label_partition; then
		blkid | grep "${LVM_VG_NAME}" >> "${DEST}/${LOG_SUBPATH}/lvm.log" 2>&1
		display_alert "LVM labeled ${ROOTFS_TYPE} partitions" "${EXTENSION}" "info"
	else
		display_alert "LVM failed to label ${ROOTFS_TYPE} partition. Ignoring." "${EXTENSION}" "info"
	fi
}

function post_umount_final_image__cleanup_lvm() {
	execute_and_remove_cleanup_handler cleanup_lvm
}

function cleanup_lvm() {
	vgchange -a n "${LVM_VG_NAME}" >> "${DEST}/${LOG_SUBPATH}/lvm.log" 2>&1 || true
	display_alert "LVM deactivated volume group" "${EXTENSION}" "info"
}
