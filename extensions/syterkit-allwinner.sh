#
# SPDX-License-Identifier: GPL-2.0
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/

# This writes the SyterKit bootloader img to the image.
function post_umount_final_image__write_syterkit_to_image() {
	display_alert "Finding SyterKit latest version" "from GitHub" "info"

	# Find the latest version of SyterKit from GitHub, using JSON API, curl and jq.
	declare api_url="https://api.github.com/repos/YuzukiHD/SyterKit/releases/latest"
	declare latest_version
	latest_version=$(curl -s "${api_url}" | jq -r '.tag_name')
	display_alert "Latest version of SyterKit is" "${latest_version}" "info"

	# Prepare the cache dir
	declare syterkit_cache_dir="${SRC}/cache/syterkit"
	mkdir -p "${syterkit_cache_dir}"

	declare syterkit_img_filename="${SYTERKIT_BOARD_ID}.tar.gz"
	declare -g -r syterkit_img_path="${syterkit_cache_dir}/${syterkit_img_filename}"
	display_alert "SyterKit image path" "${syterkit_img_path}" "info"

	declare download_url="https://github.com/YuzukiHD/SyterKit/releases/download/${latest_version}/${syterkit_img_filename}"

	# Download the image (with wget) if it doesn't exist; download to a temporary file first, then move to the final path.
	if [[ ! -f "${syterkit_cache_dir}/${SYTERKIT_BOARD_ID}/extlinux_boot/extlinux_boot_bin_card.bin" ]]; then
		display_alert "Downloading SyterKit image" "${download_url}" "info"
		declare tmp_syterkit_img_path="${syterkit_img_path}.tmp"
		run_host_command_logged wget -O "${tmp_syterkit_img_path}" "${download_url}"
		run_host_command_logged mv -v "${tmp_syterkit_img_path}" "${syterkit_img_path}"
		display_alert " Decompressing SyterKit image to" "${syterkit_img_path}/${SYTERKIT_BOARD_ID}" "info"
		mkdir -p ${syterkit_cache_dir}/${SYTERKIT_BOARD_ID}
		run_host_command_logged tar -zxvf ${syterkit_img_path} -C ${syterkit_cache_dir}/${SYTERKIT_BOARD_ID}
	else
		display_alert "SyterKit image already downloaded, using it" "${syterkit_img_path}" "info"
	fi

	display_alert " Writing SyterKit image" "${syterkit_img_path} to ${LOOP}" "info"
	dd if="${syterkit_cache_dir}/${SYTERKIT_BOARD_ID}/extlinux_boot/extlinux_boot_bin_card.bin" of="${LOOP}" bs=1k conv=notrunc seek=8
}
