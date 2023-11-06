# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/

# This outputs image in VHD format, for use with Hyper-V and Microsoft Azure.
# The important part is making sure the input raw file is a multiple of 1024*1024 bytes, as per Microsoft's instructions.
# Otherwise importing the VHD would fail.
# This extension is incompatible with the qcow2 equivalent.

function add_host_dependencies__vhd_host_deps() {
	declare -g SKIP_QCOW2=yes # Skip qcow2 from the image-output-qcow2 extension
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} qemu-utils"
}

function post_build_image__900_convert_to_vhd_img() {
	[[ -z $version ]] && exit_with_error "version is not set"
	display_alert "Converting image to VHD" "${EXTENSION}" "info"

	declare rawdisk="${DESTIMG}/${version}.img"
	declare vhddisk="${DESTIMG}/${version}.img.vhd"

	declare MB=$((1024 * 1024))
	declare size
	size=$(qemu-img info -f raw --output json "$rawdisk" | jq '."virtual-size"')
	display_alert "VHD" "Raw Image original Size = $size" "info"

	declare rounded_size=$((((size + MB - 1) / MB) * MB))
	declare rounded_size_adjusted=$((rounded_size + 512))

	declare -g -r -i VHD_SIZE="${rounded_size_adjusted}"
	display_alert "VHD" "Rounded Size Adjusted   = ${VHD_SIZE}" "info"

	run_host_command_logged qemu-img resize -f raw "$rawdisk" $rounded_size

	display_alert "Converting raw" "to VHD" "info"
	run_host_command_logged qemu-img convert -f raw -o subformat=fixed,force_size -O vpc "$rawdisk" "$vhddisk"

	if [[ "${VHD_KEEP_IMG}" != "yes" ]]; then
		display_alert "Discarding original .img image after" "conversion to VHD" "info"
		run_host_command_logged rm -vf "${DESTIMG}/${version}.img" "${DESTIMG}/${version}.img.txt"
	fi

	return 0
}
