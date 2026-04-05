#!/usr/bin/env bash

function fetch_sources_tools__gxlimg() {
	# Branch: master, Commit date: Nov 10, 2025 (please update when updating commit ref)
	fetch_from_repo "${GITHUB_SOURCE}/repk/gxlimg" "gxlimg" "commit:37a3ea072ca81bb3872441a09fe758340fd67dcb"
}

function build_host_tools__compile_gxlimg() {
	# Compile and install only if git commit hash changed
	cd "${SRC}/cache/sources/gxlimg" || exit
	# need to check if /usr/local/bin/gxlimg to detect new Docker containers with old cached sources
	if [[ ! -f .commit_id || $(git rev-parse @ 2> /dev/null) != $(< .commit_id) || ! -f /usr/local/bin/gxlimg ]]; then
		display_alert "Compiling" "gxlimg" "info"
		run_host_command_logged make distclean
		run_host_command_logged make
		run_host_command_logged install -Dm0755 gxlimg /usr/local/bin/gxlimg
		git rev-parse @ 2> /dev/null > .commit_id
	fi
}

# This function extracts bl2 and bl3x from the old FIP and repackages them with the new u-boot.bin into a FIP
# $1 path to old FIP file
# $2 SoC family
function gxlimg_repack_fip_with_new_uboot() {
	display_alert "${BOARD}" "Repacking FIP with new u-boot.bin" "info"

	if [[ ! -f "$1" ]]; then
		exit_with_error "FIP file $1 does not exist"
	fi
	if [[ ! -f u-boot.bin ]]; then
		exit_with_error "u-boot.bin not found under $(pwd)"
	fi

	mv u-boot.bin raw-u-boot.bin
	EXTRACT_DIR=$(mktemp -d)
	trap 'rm -rf "$EXTRACT_DIR"' EXIT
	run_host_command_logged gxlimg -e "$1" "$EXTRACT_DIR"
	rm -f "${EXTRACT_DIR}/bl33.enc"

	case $2 in
		gxl)
			run_host_command_logged gxlimg \
				-t bl3x \
				-c raw-u-boot.bin \
				"${EXTRACT_DIR}/bl33.enc"

			run_host_command_logged gxlimg \
				-t fip \
				--bl2 "${EXTRACT_DIR}/bl2.sign" \
				--bl30 "${EXTRACT_DIR}/bl30.enc" \
				--bl301 "${EXTRACT_DIR}/bl301.enc" \
				--bl31 "${EXTRACT_DIR}/bl31.enc" \
				--bl33 "${EXTRACT_DIR}/bl33.enc" \
				u-boot.bin
			;;

		g12a | g12b)
			run_host_command_logged gxlimg \
				-t bl3x \
				-s raw-u-boot.bin \
				"${EXTRACT_DIR}/bl33.enc"

			if [[ -e "${EXTRACT_DIR}/lpddr3_1d.fw" ]]; then
				run_host_command_logged gxlimg \
					-t fip \
					--bl2 "${EXTRACT_DIR}/bl2.sign" \
					--ddrfw "${EXTRACT_DIR}/ddr4_1d.fw" \
					--ddrfw "${EXTRACT_DIR}/ddr4_2d.fw" \
					--ddrfw "${EXTRACT_DIR}/ddr3_1d.fw" \
					--ddrfw "${EXTRACT_DIR}/piei.fw" \
					--ddrfw "${EXTRACT_DIR}/lpddr4_1d.fw" \
					--ddrfw "${EXTRACT_DIR}/lpddr4_2d.fw" \
					--ddrfw "${EXTRACT_DIR}/diag_lpddr4.fw" \
					--ddrfw "${EXTRACT_DIR}/aml_ddr.fw" \
					--ddrfw "${EXTRACT_DIR}/lpddr3_1d.fw" \
					--bl30 "${EXTRACT_DIR}/bl30.enc" \
					--bl31 "${EXTRACT_DIR}/bl31.enc" \
					--bl33 "${EXTRACT_DIR}/bl33.enc" \
					--rev v3 u-boot.bin
			else
				run_host_command_logged gxlimg \
					-t fip \
					--bl2 "${EXTRACT_DIR}/bl2.sign" \
					--ddrfw "${EXTRACT_DIR}/ddr4_1d.fw" \
					--ddrfw "${EXTRACT_DIR}/ddr4_2d.fw" \
					--ddrfw "${EXTRACT_DIR}/ddr3_1d.fw" \
					--ddrfw "${EXTRACT_DIR}/piei.fw" \
					--ddrfw "${EXTRACT_DIR}/lpddr4_1d.fw" \
					--ddrfw "${EXTRACT_DIR}/lpddr4_2d.fw" \
					--ddrfw "${EXTRACT_DIR}/diag_lpddr4.fw" \
					--ddrfw "${EXTRACT_DIR}/aml_ddr.fw" \
					--bl30 "${EXTRACT_DIR}/bl30.enc" \
					--bl31 "${EXTRACT_DIR}/bl31.enc" \
					--bl33 "${EXTRACT_DIR}/bl33.enc" \
					--rev v3 u-boot.bin
			fi
			;;

		*)
			exit_with_error "Unsupported SoC family: $2"
			;;
	esac

	if [[ ! -s u-boot.bin ]]; then
		exit_with_error "FIP repack produced empty u-boot.bin"
	fi
}
