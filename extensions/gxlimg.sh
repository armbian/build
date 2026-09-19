#!/usr/bin/env bash
# @description Builds the `gxlimg` host tool for packaging Amlogic bootable images. Fetches `repk/gxlimg` at a pinned commit, compiles it. Provides `gxlimg_repack_fip_with_new_uboot`, which extracts BL2/BL3x from an existing FIP and repacks them with a fresh `u-boot.bin` for `gxl`/`g12a`/`g12b` SoCs.

function fetch_sources_tools__gxlimg() {
	# Branch: master, Commit date: 4th commit in Nov 10, 2025 (please update when updating commit ref)
	fetch_from_repo "${GITHUB_SOURCE}/repk/gxlimg" "gxlimg" "commit:d7a8d33ef7d330a8dc77f3f53ab1e12b00a6ec8f"
}

function build_host_tools__compile_gxlimg() {
	display_alert "Compiling" "gxlimg" "info"
	cd "${SRC}/cache/sources/gxlimg" || exit_with_error "Could not find glximg source dir"
	run_host_command_logged make distclean
	run_host_command_logged make DEBUG=1
}

# This function extracts bl2 and bl3x from the old FIP and repackages them with the new u-boot.bin into a FIP
# $1 path to old FIP file
# $2 SoC family
function gxlimg_repack_fip_with_new_uboot() {
	display_alert "${BOARD}" "Repacking FIP with new u-boot.bin" "info"

	declare glximg_bin="${SRC}/cache/sources/gxlimg/gxlimg"
	if [[ ! -f "${glximg_bin}" ]]; then
		exit_with_error "gxlimg bin not found in ${glximg_bin}"
	fi

	if [[ ! -f "$1" ]]; then
		exit_with_error "FIP file $1 does not exist"
	fi
	if [[ ! -f u-boot.bin ]]; then
		exit_with_error "u-boot.bin not found under $(pwd)"
	fi

	run_host_command_logged mv -v u-boot.bin raw-u-boot.bin
	declare gxlimg_extract_temp_dir
	gxlimg_extract_temp_dir="$(mktemp -d)" # this is under TMPDIR, so so need to clean it up
	display_alert "${BOARD}" "Extracting FIP to ${gxlimg_extract_temp_dir}" "info"
	run_host_command_logged "${glximg_bin}" -e "$1" "${gxlimg_extract_temp_dir}"
	run_host_command_logged tree "${gxlimg_extract_temp_dir}"

	# drop the extracted bl33.enc, as we will replace it.
	run_host_command_logged rm -fv "${gxlimg_extract_temp_dir}/bl33.enc"

	case $2 in
		gxl)
			display_alert "${BOARD} gxlimg gxl" "Encrypting new bl33 from incoming u-boot" "info"
			run_host_command_logged "${glximg_bin}" \
				-t bl3x \
				-c raw-u-boot.bin \
				"${gxlimg_extract_temp_dir}/bl33.enc"

			display_alert "${BOARD} gxlimg gxl" "Repacking FIP with new bl33" "info"
			run_host_command_logged "${glximg_bin}" \
				-t fip \
				--bl2 "${gxlimg_extract_temp_dir}/bl2.sign" \
				--bl30 "${gxlimg_extract_temp_dir}/bl30.enc" \
				--bl301 "${gxlimg_extract_temp_dir}/bl301.enc" \
				--bl31 "${gxlimg_extract_temp_dir}/bl31.enc" \
				--bl33 "${gxlimg_extract_temp_dir}/bl33.enc" \
				u-boot.bin
			;;

		g12a | g12b)
			run_host_command_logged "${glximg_bin}" \
				-t bl3x \
				-s raw-u-boot.bin \
				"${gxlimg_extract_temp_dir}/bl33.enc"

			if [[ -e "${gxlimg_extract_temp_dir}/lpddr3_1d.fw" ]]; then
				run_host_command_logged "${glximg_bin}" \
					-t fip \
					--bl2 "${gxlimg_extract_temp_dir}/bl2.sign" \
					--ddrfw "${gxlimg_extract_temp_dir}/ddr4_1d.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/ddr4_2d.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/ddr3_1d.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/piei.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/lpddr4_1d.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/lpddr4_2d.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/diag_lpddr4.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/aml_ddr.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/lpddr3_1d.fw" \
					--bl30 "${gxlimg_extract_temp_dir}/bl30.enc" \
					--bl31 "${gxlimg_extract_temp_dir}/bl31.enc" \
					--bl33 "${gxlimg_extract_temp_dir}/bl33.enc" \
					--rev v3 u-boot.bin
			else
				run_host_command_logged "${glximg_bin}" \
					-t fip \
					--bl2 "${gxlimg_extract_temp_dir}/bl2.sign" \
					--ddrfw "${gxlimg_extract_temp_dir}/ddr4_1d.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/ddr4_2d.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/ddr3_1d.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/piei.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/lpddr4_1d.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/lpddr4_2d.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/diag_lpddr4.fw" \
					--ddrfw "${gxlimg_extract_temp_dir}/aml_ddr.fw" \
					--bl30 "${gxlimg_extract_temp_dir}/bl30.enc" \
					--bl31 "${gxlimg_extract_temp_dir}/bl31.enc" \
					--bl33 "${gxlimg_extract_temp_dir}/bl33.enc" \
					--rev v3 u-boot.bin
			fi
			;;

		*)
			exit_with_error "Unsupported SoC family for gxlimg: $2"
			;;
	esac

	if [[ ! -s u-boot.bin ]]; then
		exit_with_error "FIP repack produced empty u-boot.bin during glximg"
	fi

	return 0
}
