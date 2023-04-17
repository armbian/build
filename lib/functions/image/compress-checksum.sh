#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function output_images_compress_and_checksum() {
	[[ -n $SEND_TO_SERVER ]] && return 0

	# check that 'version' is set
	[[ -z $version ]] && exit_with_error "version is not set"
	# compression_type: declared in outer scope

	declare prefix_images="${1}"
	# find all files that match prefix_images
	declare -a images=("${prefix_images}"*)
	# if no files match prefix_images, exit
	if [[ ${#images[@]} -eq 0 ]]; then
		display_alert "No files to compress and checksum" "no images will be compressed" "wrn"
		return 0
	fi

	# loop over images
	for uncompressed_file in "${images[@]}"; do
		# if image is a symlink, skip it
		[[ -L "${uncompressed_file}" ]] && continue
		# if image is not a file, skip it
		[[ ! -f "${uncompressed_file}" ]] && continue
		# if filename ends in .txt, skip it
		[[ "${uncompressed_file}" == *.txt ]] && continue

		# get just the filename, sans path
		declare uncompressed_file_basename
		uncompressed_file_basename=$(basename "${uncompressed_file}")

		if [[ $COMPRESS_OUTPUTIMAGE == *xz* ]]; then
			display_alert "Compressing with xz" "${uncompressed_file_basename}.xz" "info"
			xz -T 0 -1 "${uncompressed_file}" # "If xz is provided with input but no output, it will delete the input"
			compression_type=".xz"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *sha* ]]; then
			display_alert "SHA256 calculating" "${uncompressed_file_basename}${compression_type}" "info"
			sha256sum -b "${uncompressed_file}${compression_type}" > "${uncompressed_file}${compression_type}".sha
		fi

	done

}
