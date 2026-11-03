#!/usr/bin/env bash
# @description Creates USB burn images for JetHub J80/J100/J200/J310. J310 uses GPT on eMMC and preserves the SD image.

#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2025-2026 JetHome
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Extension: jethub-burn
# Automatically converts Armbian .img into burn image after build

# Download and prepare tools
function bootstrap_tools() {
	local repo_url="https://github.com/jethome-iot/jethome-tools.git"
	local ref="commit:5d484fe49782a20e44d4ed14db0ca8d53c27a07d"

	display_alert "jethub-burn" "Fetching jethome-tools (${ref})..." "info"
	fetch_from_repo "${repo_url}" "jethome-tools" "${ref}"

	declare -g TOOLS_DIR="${SRC}/cache/sources/jethome-tools"
	declare -g PACKER="${TOOLS_DIR}/tools/aml_image_v2_packer_new"
	declare -g BINS_DIR="${TOOLS_DIR}/bins"
	declare -g DTS_DIR="${TOOLS_DIR}/dts"
	declare -g DTBTOOLS_DIR="${TOOLS_DIR}/dtbtools"
	declare -g IMAGE_CFG="${BINS_DIR}/image.armbian.cfg"

	[[ -x "${PACKER}" ]] || exit_with_error "aml_image_v2_packer_new not found at ${PACKER}"

	declare -g JETHOME_TOOLS_CACHE="${SRC}/cache/jethome"
	export JETHOME_TOOLS_CACHE
	run_host_command_logged mkdir -p "${JETHOME_TOOLS_CACHE}/recovery"
	source "${TOOLS_DIR}/lib.sh"

	display_alert "jethub-burn" "Tools ready (packer: ${PACKER})" "ok"
}

# Cleanup handlers for temporary directories
declare -g JETHUB_BURN_TMPDIR=""
declare -g JETHUB_UBOOT_TMPDIR=""

function cleanup_burn_tmpdir() {
	[[ -d "${JETHUB_BURN_TMPDIR}" ]] && rm -rf "${JETHUB_BURN_TMPDIR}"
}

function cleanup_uboot_tmpdir() {
	[[ -d "${JETHUB_UBOOT_TMPDIR}" ]] && rm -rf "${JETHUB_UBOOT_TMPDIR}"
}

function make_burn__j310_gpt() {
	local tmpdir="$1"
	local rootfs_bytes rootfs_sectors
	rootfs_bytes=$(stat -c%s "$tmpdir/part-1.img") || exit_with_error "Cannot read rootfs size"
	[[ $rootfs_bytes -gt 0 && $((rootfs_bytes % 512)) -eq 0 ]] || exit_with_error "Invalid rootfs size"
	rootfs_sectors=$((rootfs_bytes / 512))
	local -r rootfs_start=$((336 * 2048))
	local -r slot_sectors=$((102 * 2048))
	local -r gpt_image="$tmpdir/emmc-gpt.img"

	# Keep rootfs as partition 1 for the existing boot script.
	# Reserve space after rootfs for the backup GPT.
	truncate -s "$(((rootfs_start + rootfs_sectors + 2048) * 512))" "$gpt_image" || exit_with_error "Cannot create GPT image"
	sfdisk --no-reread --no-tell-kernel "$gpt_image" <<- EOF || exit_with_error "Cannot create J310 GPT"
		label: gpt
		unit: sectors
		sector-size: 512
		start=$rootfs_start, size=$rootfs_sectors, type=L, name="rootfs"
		start=$((132 * 2048)), size=$slot_sectors, type=L, name="recovery_a"
		start=$((234 * 2048)), size=$slot_sectors, type=L, name="recovery_b"
	EOF
	dd if="$gpt_image" of="$tmpdir/gpt.bin" bs=512 count=34 status=none || exit_with_error "Cannot extract J310 GPT"
	rm -f "$gpt_image"
}

# Build burn image
function make_burn__run() {
	local -r input_img="$1"
	local -r board="$2"
	local -r dts_name="$3"
	local -r bins_subdir="$4"
	local -r uboot_bin="$5"
	local -r soc_family="$6"
	local -r recovery_slots="$7"

	local -r bins="${BINS_DIR}/${bins_subdir}"
	[[ -d "${bins}" ]] || exit_with_error "bins directory not found: ${bins}"

	# s7 (j310) packs a different file set
	local dtsi_name image_cfg packer
	dtsi_name="partition_arm.dtsi"
	if [[ "${soc_family}" == "s7" ]]; then
		image_cfg="${BINS_DIR}/image.armbian.s7-gpt.cfg"
		packer="${TOOLS_DIR}/tools/aml_image_v2_packer_new.s7"
	else
		image_cfg="${IMAGE_CFG}"
		packer="${PACKER}"
	fi
	[[ -f "${image_cfg}" ]] || exit_with_error "Update jethome-tools ref: configuration missing at ${image_cfg}"
	[[ -x "${packer}" ]] || exit_with_error "packer not found at ${packer}"
	JETHUB_BURN_TMPDIR="$(mktemp -d)"
	local -r tmpdir="${JETHUB_BURN_TMPDIR}"
	add_cleanup_handler cleanup_burn_tmpdir

	[[ -n "${version}" ]] || exit_with_error "version is not set"
	local -r OUT_IMG="${DESTIMG}/${version}.burn.img"

	display_alert "make_burn" "Building burn image for ${board}" "info"

	# build _aml_dtb.PARTITION
	mkdir -p "$tmpdir/dts"
	cp "$DTS_DIR/$dts_name" "$tmpdir/dts/$dts_name"
	cp "$DTS_DIR/$dtsi_name" "$tmpdir/dts/$dtsi_name"
	sed -i "s#partition\.dtsi#${dtsi_name}#g" "$tmpdir/dts/$dts_name"

	cpp -nostdinc -I "$DTS_DIR" -I "$DTS_DIR/include" -undef -x assembler-with-cpp "$tmpdir/dts/$dts_name" "$tmpdir/${dts_name}.pre"
	dtc -I dts -O dtb -p 0x1000 -qqq "$tmpdir/${dts_name}.pre" -o "$tmpdir/board.dtb"

	cc -O2 -o "$tmpdir/dtbTool" "$DTBTOOLS_DIR/dtbTool.c"
	"$tmpdir/dtbTool" -o "$tmpdir/_aml_dtb.PARTITION" "$tmpdir"
	display_alert "make_burn" "_aml_dtb.PARTITION built" "info"

	display_alert "make_burn" "Extracting partitions..." "info"

	# Extract partitions using sfdisk to get offsets
	local partition_count=0
	local start size line
	while IFS= read -r line; do
		partition_count=$((partition_count + 1))
		start=$(echo "$line" | sed 's/.*start= *\([0-9]*\).*/\1/')
		size=$(echo "$line" | sed 's/.*size= *\([0-9]*\).*/\1/')
		# Validate parsed values before dd
		[[ "$start" =~ ^[0-9]+$ ]] || exit_with_error "Failed to parse partition ${partition_count} start offset from sfdisk"
		[[ "$size" =~ ^[0-9]+$ && "$size" -gt 0 ]] || exit_with_error "Failed to parse partition ${partition_count} size from sfdisk"
		display_alert "make_burn" "Extracting partition ${partition_count} (start=${start}, size=${size})" "info"
		dd if="$input_img" of="$tmpdir/part-${partition_count}.img" bs=512 skip="$start" count="$size" status=none || exit_with_error "dd failed for partition ${partition_count}"
		[[ $(stat -c%s "$tmpdir/part-${partition_count}.img") -eq $((size * 512)) ]] || exit_with_error "Truncated partition ${partition_count}"
	done < <(sfdisk -d "$input_img" 2> /dev/null | grep 'start=')

	if [[ ${partition_count} -eq 0 ]]; then
		exit_with_error "No partitions found in $input_img"
	elif [[ ${partition_count} -gt 1 ]]; then
		exit_with_error "Expected 1 partition, found ${partition_count}"
	fi

	# Recovery slots retain their fixed offsets on eMMC.
	if [[ "${recovery_slots}" == "yes" ]]; then
		local recovery_fit fit_bytes
		local -r slot_bytes=$((102 * 1024 * 1024))
		recovery_fit="$(ensure_recovery_fit "${board#jethub}")" || exit_with_error "Could not obtain recovery.fit for ${board}"
		fit_bytes=$(stat -c%s "${recovery_fit}")
		[[ ${fit_bytes} -le ${slot_bytes} ]] || exit_with_error "recovery.fit is ${fit_bytes} bytes, does not fit the ${slot_bytes} byte slot"

		cp "${recovery_fit}" "$tmpdir/recovery_a.img"
		cp "${recovery_fit}" "$tmpdir/recovery_b.img"
		if [[ "${soc_family}" == "s7" ]]; then
			display_alert "make_burn" "Creating GPT with rootfs and recovery partitions" "info"
			make_burn__j310_gpt "$tmpdir"
			truncate -s "$(((fit_bytes + 511) / 512 * 512))" "$tmpdir/recovery_a.img" "$tmpdir/recovery_b.img"
		else
			truncate -s ${slot_bytes} "$tmpdir/recovery_a.img" "$tmpdir/recovery_b.img"
			cat "$tmpdir/recovery_a.img" "$tmpdir/recovery_b.img" "$tmpdir/part-1.img" > "$tmpdir/part-1.img.new"
			mv "$tmpdir/part-1.img.new" "$tmpdir/part-1.img"
			rm -f "$tmpdir/recovery_a.img" "$tmpdir/recovery_b.img"
		fi
	fi

	cp "$bins/platform.conf" "$tmpdir/"
	cp "$image_cfg" "$tmpdir/image.cfg"
	if [[ "${soc_family}" == "s7" ]]; then
		cp "$uboot_bin" "$tmpdir/u-boot.bin"
		cp "${uboot_bin%/*}/u-boot.bin.usb" "$tmpdir/"
		cp "$bins/usb_flow.aml" "$tmpdir/"
	else
		cp "$bins/DDR.USB" "$tmpdir/"
		cp "$bins/UBOOT.USB" "$tmpdir/"
		cp "$uboot_bin" "$tmpdir/u-boot.bin"
	fi

	display_alert "make_burn" "Packing burn image..." "info"
	run_host_x86_binary_logged "$packer" -r "$tmpdir/image.cfg" "$tmpdir" "$OUT_IMG" || exit_with_error "Image pack FAILED"

	[[ -f "$OUT_IMG" ]] || exit_with_error "Burn image not produced"
	display_alert "make_burn" "Burn image created: $(basename "$OUT_IMG")" "ok"

	execute_and_remove_cleanup_handler cleanup_burn_tmpdir
}

function post_build_image__900_jethub_burn() {
	[[ -z $version ]] && exit_with_error "version is not set"

	local -r original_image_file="${DESTIMG}/${version}.img"
	[[ -f "$original_image_file" ]] || exit_with_error "Original image not found: $original_image_file"

	local dts_name bins_subdir
	local soc_family="legacy" recovery_slots="no"
	case "${BOARD}" in
		jethubj80) dts_name="meson-gxl-s905w-jethome-jethub-j80.dts" bins_subdir="j80" ;;
		jethubj100) dts_name="meson-axg-jethome-jethub-j100.dts" bins_subdir="j100" ;;
		jethubj200) dts_name="meson-sm1-jethome-jethub-j200.dts" bins_subdir="j200" ;;
		jethubj310)
			dts_name="meson-s7-jethub-j310.dts" bins_subdir="j310-armbian"
			soc_family="s7" recovery_slots="yes"
			;;
		*) exit_with_error "Unsupported board: ${BOARD} (supported: j80, j100, j200, j310)" ;;
	esac

	display_alert "Converting image to Amlogic burn format" "jethub-burn :: ${BOARD}" "info"

	bootstrap_tools

	local uboot_bin
	local -r uboot_deb="${DEB_STORAGE}/${image_artifacts_debs_reversioned["uboot"]}"
	[[ -f "${uboot_deb}" ]] || exit_with_error "u-boot deb not found for ${BOARD}: ${uboot_deb}"
	JETHUB_UBOOT_TMPDIR="$(mktemp -d)"
	local -r tmp_dir="${JETHUB_UBOOT_TMPDIR}"
	add_cleanup_handler cleanup_uboot_tmpdir

	mkdir -p "${tmp_dir}/deb-uboot"
	dpkg -x "${uboot_deb}" "${tmp_dir}/deb-uboot"
	uboot_bin=$(find "${tmp_dir}/deb-uboot/usr/lib" -type f -name "u-boot.nosd.bin" | head -n1)
	[[ -n "${uboot_bin}" ]] || exit_with_error "u-boot.nosd.bin not found in deb"
	if [[ "${soc_family}" == "s7" ]]; then
		[[ -f "${uboot_bin%/*}/u-boot.bin.usb" ]] || exit_with_error "Rebuild J310 U-Boot: USB binary missing in deb"
	fi

	make_burn__run "${original_image_file}" "${BOARD}" "${dts_name}" "${bins_subdir}" \
		"${uboot_bin}" "${soc_family}" "${recovery_slots}"

	execute_and_remove_cleanup_handler cleanup_uboot_tmpdir

	display_alert "jethub-burn" "Burn image prepared (pre-checksum stage)" "ok"
}
