#!/usr/bin/env bash
# @description Build UUID-search GRUB for Lenovo Y700 Gen4 and split the final GPT image into EFI/rootfs images.

# EFI_SECTOR_SIZE selects the FAT logical sector size (512/1024/2048/4096).
# ROOTFS_BLOCK_SIZE selects the ext4 block size (1024/2048/4096).
# Both default to 4096 for the device's UFS logical sector size.
# ROOTFS_BLOCK_SIZE applies to both the full image and the exported rootfs.
# Armbian's SECTOR_SIZE controls the input GPT image's logical sector size.

# grub-with-dtb enables the base grub extension as well.
enable_extension "grub-with-dtb"

function add_host_dependencies__lenovo_y700_gen4_grub_split_image() {
	EXTRA_BUILD_DEPS+=("lenovo-y700-gen4-grub-split-image::mtools")
}

# Set ext4 blocks before copying files, so extraction preserves all inode metadata.
function pre_prepare_partitions__lenovo_y700_gen4_rootfs_block_size() {
	[[ "${UEFI_GRUB:-}" == "skip" ]] && return 0
	local block_size="${ROOTFS_BLOCK_SIZE:-4096}"
	case "${block_size}" in
		1024 | 2048 | 4096) ;;
		*) exit_with_error "ROOTFS_BLOCK_SIZE must be 1024, 2048 or 4096 bytes" ;;
	esac
	mkopts["ext4"]+=" -b ${block_size}"
}

# Repartitioning invalidates GRUB's disk-relative prefix. Locate /boot/grub by filesystem UUID.
function grub_late_config__uuid_prefix() {
	[[ "${CRYPTROOT_ENABLE:-no}" != "yes" && "${ROOTFS_TYPE:-}" == "ext4" && "${UEFI_MOUNT_POINT}" == "/boot/efi" ]] ||
		exit_with_error "UUID GRUB requires unencrypted ext4 rootfs and a separate ESP"
	[[ "${UEFI_GRUB_TARGET}" == "arm64-efi" && "${BOOTSIZE}" == "0" ]] ||
		exit_with_error "UUID GRUB requires arm64-efi and /boot on rootfs"
	[[ "${ROOT_PART_UUID:-}" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] ||
		exit_with_error "Missing or invalid root filesystem UUID for GRUB"

	local early_cfg="/boot/grub/early-uuid.cfg"
	local efi_file="${UEFI_MOUNT_POINT}/EFI/BOOT/BOOTAA64.EFI"
	if ! cat 2>&1 > "${MOUNT}${early_cfg}" <<- EOF
		search --no-floppy --fs-uuid --set=root ${ROOT_PART_UUID}
		set prefix=(\$root)/boot/grub
		insmod normal
		normal
	EOF
	then
		exit_with_error "Failed to write GRUB UUID configuration" "${MOUNT}${early_cfg}"
	fi

	display_alert "Installing UUID-search GRUB EFI" "${ROOT_PART_UUID}" "info"
	chroot_custom "${MOUNT}" grub-mkimage \
		-O arm64-efi -d /usr/lib/grub/arm64-efi -p /boot/grub \
		-c "${early_cfg}" -o "${efi_file}.new" \
		part_gpt fat ext2 search search_fs_uuid normal configfile ||
		exit_with_error "Failed to generate UUID-search GRUB EFI"
	[[ -s "${MOUNT}${efi_file}.new" ]] ||
		exit_with_error "Generated GRUB EFI is empty"
	mv -fT "${MOUNT}${efi_file}.new" "${MOUNT}${efi_file}" 2>&1 ||
		exit_with_error "Failed to install UUID-search GRUB EFI" "${MOUNT}${efi_file}"
}

function lenovo_y700_gen4_check_image_property() {
	local image="$1" property="$2" expected="$3" actual
	actual=$(blkid -p -s "${property}" -o value "${image}") || {
		printf 'Failed to read %s from %s\n' "${property}" "${image}" >&2
		return 1
	}
	[[ "${actual}" == "${expected}" ]] || {
		printf '%s: %s mismatch: expected %s, got %s\n' "${image}" "${property}" "${expected}" "${actual}" >&2
		return 1
	}
}

# Lenovo Y700 Gen4 exposes 4096-byte UFS logical sectors. A 512-byte-sector FAT ESP fails after flashing:
# FAT-fs (sda17): logical sector size too small for device (logical sector size = 512)
# Rebuild only the exported ESP. Preserve the FAT filesystem in the full image.
function lenovo_y700_gen4_set_efi_sector_size() (
	local stage="$1" target_sector_size="$2" current_sector_size uuid label fat_version image_bytes
	cd -- "${stage}" || {
		printf 'Failed to enter EFI staging directory: %s\n' "${stage}" >&2
		return 1
	}
	image_bytes=$(stat -c %s efi.img) || {
		printf 'Failed to read EFI image size\n' >&2
		return 1
	}
	[[ $((image_bytes % target_sector_size)) -eq 0 ]] || {
		printf 'EFI image size is not aligned to %s bytes\n' "${target_sector_size}" >&2
		return 1
	}
	current_sector_size=$(blkid -p -s BLOCK_SIZE -o value efi.img) || {
		printf 'Failed to read EFI logical sector size\n' >&2
		return 1
	}
	[[ "${current_sector_size}" == "${target_sector_size}" ]] && return 0
	uuid=$(blkid -p -s UUID -o value efi.img) || {
		printf 'Failed to read EFI filesystem UUID\n' >&2
		return 1
	}
	fat_version=$(blkid -p -s VERSION -o value efi.img) || {
		printf 'Failed to read EFI FAT version\n' >&2
		return 1
	}
	# A missing label is valid. Confirm that the filesystem remains readable.
	label=$(blkid -p -s LABEL -o value efi.img) || {
		[[ $? -eq 2 ]] || {
			printf 'Failed to read EFI volume label\n' >&2
			return 1
		}
		lenovo_y700_gen4_check_image_property efi.img TYPE vfat || return 1
		label=""
	}
	case "${fat_version}" in
		FAT12 | FAT16 | FAT32) ;;
		*)
			printf 'Unsupported EFI FAT version: %s\n' "${fat_version}" >&2
			return 1
			;;
	esac
	truncate -s "${image_bytes}" efi.img.rebuilt || {
		printf 'Failed to allocate rebuilt EFI image: %s bytes\n' "${image_bytes}" >&2
		return 1
	}
	local -a fat_args=(-F "${fat_version#FAT}" -S "${target_sector_size}" -i "${uuid//-/}")
	[[ -z "${label}" ]] || fat_args+=(-n "${label}")
	mkfs.fat "${fat_args[@]}" efi.img.rebuilt || {
		printf 'Failed to format EFI image\n' >&2
		return 1
	}
	# Copy directly between FAT images without allocating loop devices or mounting filesystems.
	if ! cat > mtools.conf <<- 'EOF'
		drive s: file="efi.img"
		drive t: file="efi.img.rebuilt"
	EOF
	then
		printf 'Failed to write mtools configuration\n' >&2
		return 1
	fi
	MTOOLSRC="${PWD}/mtools.conf" mcopy -s -p -m -Q 's:/*' 't:/' || {
		printf 'Failed to copy EFI files\n' >&2
		return 1
	}
	sync -d efi.img.rebuilt || {
		printf 'Failed to sync rebuilt EFI image\n' >&2
		return 1
	}
	lenovo_y700_gen4_check_image_property efi.img.rebuilt BLOCK_SIZE "${target_sector_size}" || return 1
	lenovo_y700_gen4_check_image_property efi.img.rebuilt UUID "${uuid}" || return 1
	rm -- mtools.conf || {
		printf 'Failed to remove mtools configuration\n' >&2
		return 1
	}
	mv -T -- efi.img.rebuilt efi.img || {
		printf 'Failed to replace EFI image with rebuilt filesystem\n' >&2
		return 1
	}
)

# Read partition byte ranges directly. Container /dev nodes need not exist.
function lenovo_y700_gen4_split_grub_image() {
	local input="$1" stage="$2" efi_sector_size="$3" rootfs_block_size="$4"
	local partition_table partition_ranges image_bytes
	local efi_offset_bytes efi_size_bytes rootfs_offset_bytes rootfs_size_bytes
	local -a sfdisk_args=(--json)
	# Raw image files do not expose their logical sector size. Match Armbian's partitioning configuration.
	if [[ "${SECTOR_SIZE:-512}" != 512 ]]; then
		sfdisk_args+=(--sector-size "${SECTOR_SIZE}")
	fi
	partition_table=$(sfdisk "${sfdisk_args[@]}" "${input}") || {
		printf 'Failed to read GPT partition table\n' >&2
		return 1
	}
	partition_ranges=$(jq -er '
		.partitiontable |
		if .label != "gpt" or (.partitions | length) != 2 then
			error("Expected a GPT image with two partitions")
		else
			.sectorsize as $sector |
			[.partitions[] | (.start * $sector), (.size * $sector)] | @tsv
		end
	' <<< "${partition_table}") || {
		printf 'Failed to parse GPT partition ranges\n' >&2
		return 1
	}
	read -r efi_offset_bytes efi_size_bytes rootfs_offset_bytes rootfs_size_bytes <<< "${partition_ranges}" || {
		printf 'Failed to read parsed GPT partition ranges\n' >&2
		return 1
	}
	image_bytes=$(stat -c %s "${input}") || {
		printf 'Failed to read GPT image size: %s\n' "${input}" >&2
		return 1
	}
	[[ ${efi_offset_bytes} -gt 0 && ${efi_size_bytes} -gt 0 && ${rootfs_size_bytes} -gt 0 &&
		$((efi_offset_bytes + efi_size_bytes)) -le ${rootfs_offset_bytes} &&
		$((rootfs_offset_bytes + rootfs_size_bytes)) -le ${image_bytes} ]] || {
		printf 'Invalid GPT partition ranges\n' >&2
		return 1
	}
	dd if="${input}" of="${stage}/efi.img" bs=4M iflag=skip_bytes,count_bytes \
		skip="${efi_offset_bytes}" count="${efi_size_bytes}" conv=sparse,fsync status=none || {
		printf 'Failed to extract EFI partition\n' >&2
		return 1
	}
	dd if="${input}" of="${stage}/rootfs.img" bs=4M iflag=skip_bytes,count_bytes \
		skip="${rootfs_offset_bytes}" count="${rootfs_size_bytes}" conv=sparse,fsync status=none || {
		printf 'Failed to extract rootfs partition\n' >&2
		return 1
	}
	[[ "$(stat -c %s "${stage}/efi.img")" == "${efi_size_bytes}" ]] || {
		printf 'Extracted EFI image must contain %s bytes\n' "${efi_size_bytes}" >&2
		return 1
	}
	[[ "$(stat -c %s "${stage}/rootfs.img")" == "${rootfs_size_bytes}" ]] || {
		printf 'Extracted rootfs image must contain %s bytes\n' "${rootfs_size_bytes}" >&2
		return 1
	}
	lenovo_y700_gen4_check_image_property "${stage}/efi.img" TYPE vfat || return 1
	lenovo_y700_gen4_check_image_property "${stage}/rootfs.img" TYPE ext4 || return 1
	lenovo_y700_gen4_check_image_property "${stage}/rootfs.img" BLOCK_SIZE "${rootfs_block_size}" || return 1
	lenovo_y700_gen4_check_image_property "${stage}/rootfs.img" UUID "${ROOT_PART_UUID}" || return 1
	lenovo_y700_gen4_set_efi_sector_size "${stage}" "${efi_sector_size}"
}

# Run after the raw GPT image is closed, before Armbian compresses/moves the
# version-prefixed files to output/images. The original full .img is not
# reformatted. Its rootfs already uses the requested ext4 block size.
function post_build_image__lenovo_y700_gen4_export_ufs_partitions() {
	[[ "${UEFI_GRUB:-}" == "skip" ]] && return 0
	[[ -s "${FINAL_IMAGE_FILE:-}" ]] || exit_with_error "Missing completed GRUB image for UFS split"
	local stage efi_image rootfs_image error_message=""
	local efi_sector_size="${EFI_SECTOR_SIZE:-4096}"
	local rootfs_block_size="${ROOTFS_BLOCK_SIZE:-4096}"
	case "${efi_sector_size}" in
		512 | 1024 | 2048 | 4096) ;;
		*) exit_with_error "EFI_SECTOR_SIZE must be 512, 1024, 2048 or 4096 bytes" ;;
	esac
	case "${rootfs_block_size}" in
		1024 | 2048 | 4096) ;;
		*) exit_with_error "ROOTFS_BLOCK_SIZE must be 1024, 2048 or 4096 bytes" ;;
	esac
	# version is supplied by Armbian's image finalization function.
	# shellcheck disable=SC2154
	efi_image="${DESTIMG}/${version}.efi.img"
	rootfs_image="${DESTIMG}/${version}.rootfs.img"
	if [[ -e "${efi_image}" || -L "${efi_image}" || -e "${rootfs_image}" || -L "${rootfs_image}" ]]; then
		exit_with_error "UFS partition image already exists" "${efi_image}, ${rootfs_image}"
	fi
	# Capture stderr outside the substitution so errors enter the build log, not the path variable.
	{ stage=$(mktemp -d "${DESTIMG}/y700-gen4-grub-split.XXXXXX"); } 2>&1 ||
		exit_with_error "Cannot stage UFS partition exports" "${DESTIMG}"
	display_alert "Splitting GRUB image" "${FINAL_IMAGE_FILE}: EFI sectors=${efi_sector_size}, ext4 blocks=${rootfs_block_size}; stage=${stage}" "info"
	if ! lenovo_y700_gen4_split_grub_image "${FINAL_IMAGE_FILE}" "${stage}" "${efi_sector_size}" "${rootfs_block_size}" 2>&1; then
		error_message="Failed to export EFI and rootfs from GRUB image"
	elif ! mv -T -- "${stage}/efi.img" "${efi_image}" 2>&1; then
		error_message="Failed to publish EFI image: ${efi_image}"
	elif ! mv -T -- "${stage}/rootfs.img" "${rootfs_image}" 2>&1; then
		error_message="Failed to publish rootfs image: ${rootfs_image}"
		# Do not leave an incomplete export pair after publication fails.
		rm -f -- "${efi_image}" 2>&1 || display_alert "Failed to remove incomplete EFI export" "${efi_image}" "warning"
	fi
	if [[ -n "${error_message}" ]]; then
		rm -rf -- "${stage}" 2>&1 || display_alert "Failed to remove UFS staging directory" "${stage}" "warning"
		exit_with_error "${error_message}" "${FINAL_IMAGE_FILE}"
	fi
	rmdir -- "${stage}" 2>&1 || exit_with_error "Images exported, but staging directory cleanup failed" "${stage}"
	display_alert "Exported UFS partition images" "${efi_image}, ${rootfs_image}" "info"
}
