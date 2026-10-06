#!/usr/bin/env bash
# @description Converts the finished `.img` into an Amlogic USB burn image for JetHub J80/J100/J200 boards. Fetches `jethome-iot/jethome-tools`, compiles the board DTB partition, extracts the rootfs and packs everything with `aml_image_v2_packer_new` using `u-boot.nosd.bin` from the U-Boot deb. Outputs `${version}.burn.img` alongside the normal image.

#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2025 JetHome
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Extension: jethub-burn
# Automatically converts Armbian .img into burn image after build

# Download and prepare tools
function bootstrap_tools() {
	local repo_url="${JETHOME_TOOLS_URL:-https://github.com/jethome-iot/jethome-tools.git}"
	local ref="${JETHOME_TOOLS_REF:-branch:convert_jhos}"

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
		image_cfg="${BINS_DIR}/image.armbian.s7.cfg"
		packer="${TOOLS_DIR}/tools/aml_image_v2_packer_new.s7"
	else
		image_cfg="${IMAGE_CFG}"
		packer="${PACKER}"
	fi
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
	done < <(sfdisk -d "$input_img" 2> /dev/null | grep 'start=')

	if [[ ${partition_count} -eq 0 ]]; then
		exit_with_error "No partitions found in $input_img"
	elif [[ ${partition_count} -gt 1 ]]; then
		exit_with_error "Expected 1 partition, found ${partition_count}"
	fi

	# Boards with a recovery system keep two 102 MiB raw slots ahead of rootfs
	if [[ "${recovery_slots}" == "yes" ]]; then
		local recovery_fit fit_bytes
		local -r slot_bytes=$((102 * 1024 * 1024))
		recovery_fit="$(ensure_recovery_fit "${board#jethub}")" || exit_with_error "Could not obtain recovery.fit for ${board}"
		fit_bytes=$(stat -c%s "${recovery_fit}")
		[[ ${fit_bytes} -le ${slot_bytes} ]] || exit_with_error "recovery.fit is ${fit_bytes} bytes, does not fit the ${slot_bytes} byte slot"

		display_alert "make_burn" "Prepending 2x recovery slots (102 MiB each)" "info"
		cp "${recovery_fit}" "$tmpdir/recovery_a.bin"
		cp "${recovery_fit}" "$tmpdir/recovery_b.bin"
		truncate -s ${slot_bytes} "$tmpdir/recovery_a.bin"
		truncate -s ${slot_bytes} "$tmpdir/recovery_b.bin"
		cat "$tmpdir/recovery_a.bin" "$tmpdir/recovery_b.bin" "$tmpdir/part-1.img" > "$tmpdir/part-1.img.new"
		mv "$tmpdir/part-1.img.new" "$tmpdir/part-1.img"
		rm -f "$tmpdir/recovery_a.bin" "$tmpdir/recovery_b.bin"
	fi

	cp "$bins/platform.conf" "$tmpdir/"
	cp "$image_cfg" "$tmpdir/image.cfg"
	if [[ "${soc_family}" == "s7" ]]; then
		cp "$bins/u-boot.bin" "$tmpdir/"
		cp "$bins/u-boot.bin.usb" "$tmpdir/"
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

	# s7 flashes the bootloader shipped with jethome-tools, there is no deb for it
	local uboot_bin=""
	if [[ "${soc_family}" != "s7" ]]; then
		local -r debs_dir="${DEB_STORAGE:-${SRC}/output/debs}"
		local uboot_deb
		uboot_deb=$(find "${debs_dir}" -maxdepth 1 -type f -name "linux-u-boot-${BOARD}-*.deb" | sort -V | tail -n1)
		[[ -n "${uboot_deb}" ]] || exit_with_error "u-boot deb not found for ${BOARD}"
		JETHUB_UBOOT_TMPDIR="$(mktemp -d)"
		local -r tmp_dir="${JETHUB_UBOOT_TMPDIR}"
		add_cleanup_handler cleanup_uboot_tmpdir

		mkdir -p "${tmp_dir}/deb-uboot"
		dpkg -x "${uboot_deb}" "${tmp_dir}/deb-uboot"
		uboot_bin=$(find "${tmp_dir}/deb-uboot/usr/lib" -type f -name "u-boot.nosd.bin" | head -n1)
		[[ -n "${uboot_bin}" ]] || exit_with_error "u-boot.nosd.bin not found in deb"
	fi

	make_burn__run "${original_image_file}" "${BOARD}" "${dts_name}" "${bins_subdir}" \
		"${uboot_bin}" "${soc_family}" "${recovery_slots}"

	if [[ "${soc_family}" != "s7" ]]; then
		execute_and_remove_cleanup_handler cleanup_uboot_tmpdir
	fi

	display_alert "jethub-burn" "Burn image prepared (pre-checksum stage)" "ok"
}
