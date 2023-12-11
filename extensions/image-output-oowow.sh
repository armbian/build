#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# This converts the output image to the Khadas OOWOW format.
# This format is already compressed with special xz parameters, so COMPRESS_OUTPUTIMAGE is forced to "none".

function extension_prepare_config__prepare_oowow_config() {
	display_alert "Preparing config" "${EXTENSION}" "info"

	# Disable compression, but keep sha sum if specified;
	if [[ "${COMPRESS_OUTPUTIMAGE}" == *sha* ]]; then
		declare -g COMPRESS_OUTPUTIMAGE="sha"
	else
		declare -g COMPRESS_OUTPUTIMAGE="none"
	fi

	# make sure we have the board parameters needed to convert to oowow
	if [[ "${KHADAS_OOWOW_BOARD_ID}" == "" ]]; then
		exit_with_error "KHADAS_OOWOW_BOARD_ID is not set, can't use ${EXTENSION}"
	else
		display_alert "Configured" "${EXTENSION} for Khadas board ID '${KHADAS_OOWOW_BOARD_ID}'" "info"
	fi

	return 0
}

function post_build_image__900_convert_to_oowow() {
	[[ -z $version ]] && exit_with_error "version is not set"

	declare original_image_file="${DESTIMG}/${version}.img"
	declare oowow_final_output_file="${DESTIMG}/${version}.oowow.img.xz" # Can't change ${version} prefix

	# Get xze script from Khadas.
	declare xze_revision="e24a30d2780f3c772ae80ac9495d91273d63b95e" # update this if/when Khadas releases new version
	declare xze_raw_url="https://raw.githubusercontent.com/khadas/krescue/${xze_revision}/tools/xze"
	declare xze_tool_dir="${SRC}/cache/khadas-xze"
	declare xze_tool="${xze_tool_dir}/xze-${xze_revision}"
	if [[ ! -f "${xze_tool}" ]]; then
		display_alert "Downloading xze tool" "from Khadas" "info"
		run_host_command_logged mkdir -p "${xze_tool_dir}"
		run_host_command_logged wget -O "${xze_tool}" "${xze_raw_url}"
		run_host_command_logged chmod +x "${xze_tool}"
	fi

	declare xze_params=(
		"--meta"
		"label=Armbian"
		"builder=Armbian"
		"date=$(LANG=C TZ='' date)"
		"match=BOARD=${KHADAS_OOWOW_BOARD_ID}"
		"link=https://www.armbian.com/"
		"duration=60"
		"desc=Armbian ${BOARD} ${RELEASE} ${BRANCH} ${REVISION}"
	)

	display_alert "Converting image to Khadas OOWOW format" "${EXTENSION} :: ${KHADAS_OOWOW_BOARD_ID}" "info"
	cd "${DESTIMG}" || exit_with_error "Could not cd to ${DESTIMG}"
	# xze is pretty confused about fd 1, so we need to pass "IN" and "OUT" env vars
	run_host_command_logged "IN=${original_image_file}" "OUT=${oowow_final_output_file}" bash "${xze_tool}" "-3" "${original_image_file}" "${xze_params[@]@Q}" # @Q to double escape for runner; -3 for fast compression
	cd "${SRC}" || exit_with_error "Could not cd to ${SRC}"

	if [[ ! -f "${oowow_final_output_file}" ]]; then
		exit_with_error "xze did not produce the expected output file: ${oowow_final_output_file}"
	fi

	# Remove the original, uncompressed file.
	display_alert "Discarding original .img image after" "conversion to oowow" "info"
	run_host_command_logged rm -vf "${original_image_file}"

	# Show the final metadata and compression info.
	display_alert "Final produced oowow image" "compression and meta info" "info"
	run_host_command_logged bash "${xze_tool}" "${oowow_final_output_file}"

	# Alert about the prefix requirement for removable media.
	display_alert "To use oowow with removable media" "rename file on media to '${KHADAS_OOWOW_BOARD_ID,,}-${version}.oowow.img.xz'"

	return 0
}
