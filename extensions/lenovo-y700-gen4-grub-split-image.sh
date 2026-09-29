#!/usr/bin/env bash
# @description Build UUID-search GRUB for Lenovo Y700 Gen4 and split the final GPT image into EFI/rootfs images.

# EFI_SECTOR_SIZE selects the FAT logical sector size (512/1024/2048/4096).
# ROOTFS_BLOCK_SIZE selects the ext4 block size (1024/2048/4096).
# Both default to 4096 for the device's UFS logical sector size.

# grub-with-dtb enables the base grub extension as well.
enable_extension "grub-with-dtb"

function add_host_dependencies__lenovo_y700_gen4_grub_split_image() {
	EXTRA_BUILD_DEPS+=(
		"lenovo-y700-gen4-grub-split-image::dosfstools"
		"lenovo-y700-gen4-grub-split-image::e2fsprogs"
		"lenovo-y700-gen4-grub-split-image::rsync"
	)
}

# grub-install embeds a disk-relative prefix (normally GPT p2). After the ESP
# and rootfs are flashed to separate UFS LUNs, that partition index is invalid.
function grub_late_config__uuid_prefix() {
	[[ "${CRYPTROOT_ENABLE:-no}" != "yes" && "${ROOTFS_TYPE:-}" == "ext4" && "${UEFI_MOUNT_POINT}" == "/boot/efi" ]] ||
		exit_with_error "UUID GRUB currently requires unencrypted ext4 rootfs and a separate ESP"
	[[ "${UEFI_GRUB_TARGET}" == "arm64-efi" && "${BOOTSIZE}" == "0" ]] ||
		exit_with_error "UUID GRUB requires arm64-efi and /boot on rootfs"
	[[ "${ROOT_PART_UUID:-}" =~ ^[[:xdigit:]-]+$ ]] ||
		exit_with_error "Missing or invalid root filesystem UUID for GRUB"

	local early_cfg="/boot/grub/early-uuid.cfg"
	local efi_file="${UEFI_MOUNT_POINT}/EFI/BOOT/BOOTAA64.EFI"
	cat > "${MOUNT}${early_cfg}" <<- EOF
		search --no-floppy --fs-uuid --set=root ${ROOT_PART_UUID}
		set prefix=(\$root)/boot/grub
		insmod normal
		normal
	EOF

	display_alert "Installing UUID-search GRUB EFI" "${ROOT_PART_UUID}" "info"
	chroot_custom "${MOUNT}" grub-mkimage \
		-O arm64-efi -d /usr/lib/grub/arm64-efi -p /boot/grub \
		-c "${early_cfg}" -o "${efi_file}.new" \
		part_gpt fat ext2 search search_fs_uuid normal configfile ||
		exit_with_error "Failed to generate UUID-search GRUB EFI"
	[[ -s "${MOUNT}${efi_file}.new" ]] ||
		exit_with_error "Generated GRUB EFI is empty"
	mv -f "${MOUNT}${efi_file}.new" "${MOUNT}${efi_file}"
}

# UFS exposes 4096-byte logical sectors. The whole GPT image may contain a
# 512-byte-sector FAT ESP, which Linux refuses to mount after it is flashed:
# FAT-fs (sda17): logical sector size too small for device (logical sector size = 512)
# Reformat only the extracted partition images as needed; the whole GPT image
# remains unchanged. Preserve the UUID used by GRUB and Linux.
function lenovo_y700_gen4_reblock_ufs_fs() {
	local image="$1" fs_type="$2" work="$3" target_size="$4"
	local current uuid label fat_version rebuilt="${image}.rebuilt"
	[[ $(( $(stat -c %s "${image}") % target_size )) -eq 0 ]] || return 1
	current=$(blkid -p -s BLOCK_SIZE -o value "${image}") || return 1
	[[ "${current}" == "${target_size}" ]] && return 0
	uuid=$(blkid -p -s UUID -o value "${image}") || return 1
	label=$(blkid -p -s LABEL -o value "${image}" || true)
	[[ -n "${uuid}" ]] || return 1
	truncate -s "$(stat -c %s "${image}")" "${rebuilt}" || return 1

	case "${fs_type}" in
		vfat)
			fat_version=$(blkid -p -s VERSION -o value "${image}") || return 1
			case "${fat_version}" in FAT12|FAT16|FAT32) ;; *) return 1 ;; esac
			local -a fat_args=(-F "${fat_version#FAT}" -S "${target_size}" -i "${uuid//-/}")
			[[ -z "${label}" ]] || fat_args+=(-n "${label}")
			mkfs.fat "${fat_args[@]}" "${rebuilt}" || return 1
			mount -o loop,ro "${image}" "${work}/source" || return 1
			mount -o loop "${rebuilt}" "${work}/target" || return 1
			rsync -rt --no-perms --no-owner --no-group "${work}/source/" "${work}/target/" || return 1
			;;
		ext4)
			local -a ext_args=(-F -m 0 -b "${target_size}" -U "${uuid}")
			[[ -z "${label}" ]] || ext_args+=(-L "${label}")
			mkfs.ext4 "${ext_args[@]}" "${rebuilt}" || return 1
			mount -o loop,ro,noload "${image}" "${work}/source" || return 1
			mount -o loop "${rebuilt}" "${work}/target" || return 1
			rsync -aHAX --numeric-ids --sparse --one-file-system "${work}/source/" "${work}/target/" || return 1
			;;
		*) return 1 ;;
	esac
	sync
	umount "${work}/target" || return 1
	umount "${work}/source" || return 1
	[[ "$(blkid -p -s BLOCK_SIZE -o value "${rebuilt}")" == "${target_size}" &&
		"$(blkid -p -s UUID -o value "${rebuilt}")" == "${uuid}" ]] || return 1
	mv -- "${rebuilt}" "${image}"
}

# Keep the mount points if even a lazy unmount fails; never recursively remove
# a directory that might still contain a mounted filesystem.
function lenovo_y700_gen4_split_cleanup() {
	local result="$1" work="$2" source_loop="$3" mount_dir
	for mount_dir in "${work}/target" "${work}/source"; do
		if mountpoint -q "${mount_dir}" && ! umount "${mount_dir}"; then
			printf 'Failed to unmount %s during UFS image split\n' "${mount_dir}" >&2
			result=1
			umount -l "${mount_dir}" || true
		fi
	done
	if [[ -n "${source_loop}" ]] && ! losetup -d "${source_loop}"; then
		printf 'Failed to detach %s during UFS image split\n' "${source_loop}" >&2
		result=1
	fi
	for mount_dir in "${work}/target" "${work}/source"; do
		if mountpoint -q "${mount_dir}"; then
			printf 'Keeping still-mounted work directory %s\n' "${work}" >&2
			return 1
		fi
	done
	rmdir "${work}/target" "${work}/source" "${work}" || result=1
	return "${result}"
}

# This function runs in a subshell, so its EXIT trap cannot change the build's
# own cleanup handlers. The input GPT image is never modified.
function lenovo_y700_gen4_split_ufs_image() (
	local input="$1" stage="$2" efi_sector_size="$3" rootfs_block_size="$4" source_loop="" work=""
	# Keep mount points outside DESTIMG: Armbian may remove DESTIMG on error.
	work=$(mktemp -d /dev/shm/y700-gen4-grub-split.XXXXXX) || return 1
	trap 'lenovo_y700_gen4_split_cleanup "$?" "${work}" "${source_loop}"; exit "$?"' EXIT
	mkdir -p "${work}/source" "${work}/target" || return 1

	source_loop=$(losetup --find --show --partscan "${input}") || return 1
	[[ -b "${source_loop}p1" && -b "${source_loop}p2" ]] || return 1
	dd if="${source_loop}p1" of="${stage}/efi.img" bs=4M conv=sparse,fsync status=none || return 1
	dd if="${source_loop}p2" of="${stage}/rootfs.img" bs=4M conv=sparse,fsync status=none || return 1
	[[ "$(stat -c %s "${stage}/efi.img")" == "$(( $(blockdev --getsz "${source_loop}p1") * 512 ))" ]] || return 1
	[[ "$(stat -c %s "${stage}/rootfs.img")" == "$(( $(blockdev --getsz "${source_loop}p2") * 512 ))" ]] || return 1
	[[ "$(blkid -p -s TYPE -o value "${stage}/efi.img")" == vfat ]] || return 1
	[[ "$(blkid -p -s TYPE -o value "${stage}/rootfs.img")" == ext4 ]] || return 1
	lenovo_y700_gen4_reblock_ufs_fs "${stage}/efi.img" vfat "${work}" "${efi_sector_size}" || return 1
	lenovo_y700_gen4_reblock_ufs_fs "${stage}/rootfs.img" ext4 "${work}" "${rootfs_block_size}" || return 1
	[[ "$(blkid -p -s BLOCK_SIZE -o value "${stage}/efi.img")" == "${efi_sector_size}" &&
		"$(blkid -p -s BLOCK_SIZE -o value "${stage}/rootfs.img")" == "${rootfs_block_size}" ]] || return 1
	[[ "$(blkid -p -s UUID -o value "${stage}/rootfs.img")" == "${ROOT_PART_UUID}" ]] || return 1
)

# Run after the raw GPT image is closed, before Armbian compresses/moves the
# version-prefixed files to output/images. The original full .img is not
# reformatted; only the separate .efi.img/.rootfs.img meet the UFS FS sizes.
function post_build_image__lenovo_y700_gen4_export_ufs_partitions() {
	[[ "${UEFI_GRUB:-}" == "skip" ]] && return 0
	[[ -s "${FINAL_IMAGE_FILE:-}" ]] || exit_with_error "Missing completed GRUB image for UFS split"
	local stage efi_image rootfs_image
	local efi_sector_size="${EFI_SECTOR_SIZE:-4096}"
	local rootfs_block_size="${ROOTFS_BLOCK_SIZE:-4096}"
	case "${efi_sector_size}" in
		512|1024|2048|4096) ;;
		*) exit_with_error "EFI_SECTOR_SIZE must be 512, 1024, 2048 or 4096 bytes" ;;
	esac
	case "${rootfs_block_size}" in
		1024|2048|4096) ;;
		*) exit_with_error "ROOTFS_BLOCK_SIZE must be 1024, 2048 or 4096 bytes" ;;
	esac
	stage=$(mktemp -d "${DESTIMG}/y700-gen4-grub-split.XXXXXX") || exit_with_error "Cannot stage UFS partition exports"
	# version is supplied by Armbian's image finalization function.
	# shellcheck disable=SC2154
	efi_image="${DESTIMG}/${version}.efi.img"
	rootfs_image="${DESTIMG}/${version}.rootfs.img"
	if [[ -e "${efi_image}" || -e "${rootfs_image}" ]]; then
		rmdir "${stage}"
		exit_with_error "UFS partition image already exists"
	fi
	if ! lenovo_y700_gen4_split_ufs_image "${FINAL_IMAGE_FILE}" "${stage}" "${efi_sector_size}" "${rootfs_block_size}" ||
		[[ ! -s "${stage}/efi.img" || ! -s "${stage}/rootfs.img" ]]; then
		rm -rf -- "${stage}"
		exit_with_error "Failed to export EFI and rootfs from GRUB image"
	fi
	mv -- "${stage}/efi.img" "${efi_image}"
	mv -- "${stage}/rootfs.img" "${rootfs_image}"
	rmdir "${stage}"
	display_alert "Exported UFS partition images" "${efi_image}, ${rootfs_image}" "info"
}
