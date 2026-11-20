# @description A superset of the `grub` extension that boots via DeviceTree instead of ACPI, for EFI-only ARM64 machines like the ThinkPad X13s or Phytium D2000. Requires `BOOT_FDT_FILE`/`GRUB_FDT_FILE`, and installs a kernel hook plus a custom `09_linux_with_dtb.sh` GRUB script that deploys the DTB to the boot partition. When `OVERLAY_PREFIX` is set, the hook also merges the overlays listed in `/boot/armbianEnv.txt` into that DTB with `fdtoverlay`, and reruns when the file changes.

#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# `grub-with-dtb` is a superset of `grub`, but hacked to boot using DeviceTree.
# this is useful for EFI-only-on-ARM64 such as the ThinkPad x13s, Phytium D2000, and possibly others.
# The way the kernel behaves being handled _both_ an ACPI table and a DeviceTree is controlled (at least) by:
# - "efi=noruntime" (get info from EFI/ACPI, but don't use its Runtime Services, and fall back to OF/DT when missing)
# - "acpi=off"  (don't use ACPI at all, and fall back to OF/DT completely: useful for SBCs)
# use GRUB_CMDLINE_LINUX_DEFAULT to set these options in the board file.

enable_extension "grub"

# Ensure config is sufficient for operation
function extension_prepare_config__prepare_grub_with_dtb() {
	# Make sure BOOT_FDT_FILE, or GRUB_FDT_FILE is set and not empty
	[[ -n "${BOOT_FDT_FILE:-"${GRUB_FDT_FILE}"}" ]] || exit_with_error "BOOT_FDT_FILE/GRUB_FDT_FILE is not set, required for grub-with-dtb"

	display_alert "Extension: ${EXTENSION}: Initializing config" "${BOARD}" "info"

	if [[ -n "${OVERLAY_PREFIX}" ]]; then
		declare -g BOOTENV_FILE="${BOOTENV_FILE:-grub-with-dtb.txt}"
	fi
}

# Hack the bsp-cli to:
# - write the BOOT_FDT_FILE information to a configuration file. (/etc/armbian-grub-with-dtb)
# - add a kernel install/upgrade hook to automatically deploy the DTB file to the boot partition, in a way that
#   works across Debian and Ubuntu. it reads /etc/armbian-grub-with-dtb and puts symlinks or copies in /boot/dtb-<kernel-version>
function post_family_tweaks_bsp__add_grub_with_dtb_config_file() {
	: "${destination:?}"
	display_alert "Extension: ${EXTENSION}: Adding grub-with-dtb config file" "${BOARD}" "info"
	# maybe add this to conffiles?
	cat <<- EOD > "${destination}"/etc/armbian-grub-with-dtb
		BOOT_FDT_FILE="${BOOT_FDT_FILE:-"${GRUB_FDT_FILE}"}"
		OVERLAY_PREFIX="${OVERLAY_PREFIX}"
	EOD
}

function post_family_tweaks_bsp__add_grub_with_dtb_kernel_hook() {
	: "${destination:?}"
	display_alert "Extension: ${EXTENSION}: Adding grub-with-dtb kernel hook" "${BOARD}" "info"
	run_host_command_logged mkdir -p "${destination}"/etc/kernel/postinst.d
	cat <<- 'EOD' > "${destination}"/etc/kernel/postinst.d/armbian-grub-with-dtb
		#! /bin/bash
		set -e

		declare kversion="$1" # # We're passed the version of the kernel being installed
		echo "Armbian: installing DTB for GRUB: $kversion" >&2

		if [[ ! -f /etc/armbian-grub-with-dtb ]]; then
			echo "Armbian: /etc/armbian-grub-with-dtb not found, skipping DTB for GRUB" >&2
			exit 0
		fi

		declare BOOT_FDT_FILE OVERLAY_PREFIX
		# shellcheck source=/dev/null
		source /etc/armbian-grub-with-dtb
		exec 9< /etc/armbian-grub-with-dtb
		flock 9
		declare target_dtb_file="/boot/armbian-dtb-${kversion}"
		declare source_dtb_file="/usr/lib/linux-image-${kversion}/${BOOT_FDT_FILE}"
		declare overlay_dir="/usr/lib/linux-image-${kversion}/${BOOT_FDT_FILE%%/*}/overlay"
		declare tmp_dtb_file="${target_dtb_file}.tmp"
		declare -a overlay_prefixes=() overlays=() user_overlays=() dtbos=()
		declare name prefix found
		declare -i merge_failed=0
		trap 'rm -f "${tmp_dtb_file}"' EXIT

		function armbian_env_value() {
			sed -n "s/^${1}=//p" /boot/armbianEnv.txt | tr -d '\r' | tail -n 1
		}
		if [[ -n "${OVERLAY_PREFIX}" && -f /boot/armbianEnv.txt ]]; then
			read -r -a overlay_prefixes <<< "$(armbian_env_value overlay_prefix)"
			read -r -a overlays <<< "$(armbian_env_value overlays)"
			read -r -a user_overlays <<< "$(armbian_env_value user_overlays)"
		fi

		for name in "${overlays[@]}"; do
			found=""
			for prefix in "${overlay_prefixes[@]}"; do
				if [[ -f "${overlay_dir}/${prefix}-${name}.dtbo" ]]; then
					found="${overlay_dir}/${prefix}-${name}.dtbo"
					break
				fi
			done
			if [[ -z "${found}" && -f "${overlay_dir}/${name}.dtbo" ]]; then
				found="${overlay_dir}/${name}.dtbo"
			fi
			if [[ -z "${found}" ]]; then
				echo "Armbian: overlay ${name} not found in ${overlay_dir}, skipping it" >&2
				continue
			fi
			dtbos+=("${found}")
		done

		for name in "${user_overlays[@]}"; do
			if [[ -f "/boot/overlay-user/${name}.dtbo" ]]; then
				dtbos+=("/boot/overlay-user/${name}.dtbo")
			else
				echo "Armbian: user overlay ${name} not found in /boot/overlay-user, skipping it" >&2
			fi
		done

		echo "Armbian: installing DTB for GRUB: $source_dtb_file -> $target_dtb_file" >&2
		cp "${source_dtb_file}" "${tmp_dtb_file}"
		if [[ ${#dtbos[@]} -gt 0 ]]; then
			if ! command -v fdtoverlay > /dev/null; then
				echo "Armbian: fdtoverlay not found, install device-tree-compiler" >&2
				merge_failed=1
			elif fdtoverlay -i "${source_dtb_file}" -o "${tmp_dtb_file}" "${dtbos[@]}"; then
				echo "Armbian: applied overlays: ${dtbos[*]##*/}" >&2
			else
				echo "Armbian: applying the overlays failed" >&2
				cp "${source_dtb_file}" "${tmp_dtb_file}"
				merge_failed=1
			fi
		fi
		# Only the overlay helper gets a failed merge as an error, package installs keep going
		if [[ ${merge_failed} -ne 0 && -n "${ARMBIAN_GRUB_DTB_STRICT}" ]]; then
			if [[ -f "${target_dtb_file}" ]]; then
				echo "Armbian: keeping the previous ${target_dtb_file}" >&2
			else
				mv "${tmp_dtb_file}" "${target_dtb_file}"
				echo "Armbian: installed the DTB without overlays" >&2
			fi
			exit 2
		fi
		mv "${tmp_dtb_file}" "${target_dtb_file}"
		if [[ ${merge_failed} -ne 0 ]]; then
			echo "Armbian: installed the DTB without overlays" >&2
		fi
		echo "Armbian: installing DTB for GRUB: done." >&2
	EOD
	run_host_command_logged chmod -v +x "${destination}"/etc/kernel/postinst.d/armbian-grub-with-dtb
}

function post_family_tweaks_bsp__add_grub_with_dtb_overlay_watch() {
	[[ -n "${OVERLAY_PREFIX}" ]] || return 0
	display_alert "Extension: ${EXTENSION}: Adding overlay watch for armbianEnv.txt" "${BOARD}" "info"

	declare file_added_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/usr/lib/armbian/armbian-grub-dtb-overlays" <<- 'EOD'
		#!/bin/bash
		declare env_file="/boot/armbianEnv.txt" stamp kver
		declare -i rc pass
		for pass in 1 2 3; do
			stamp="$(stat -c '%y %s' "${env_file}" 2> /dev/null)"
			rc=0
			while read -r kver; do
				ARMBIAN_GRUB_DTB_STRICT=1 /etc/kernel/postinst.d/armbian-grub-with-dtb "${kver}" || rc=1
			done < <(linux-version list)
			[[ "${stamp}" == "$(stat -c '%y %s' "${env_file}" 2> /dev/null)" ]] && break
			echo "Armbian: ${env_file} changed during pass ${pass}, rebuilding again" >&2
		done
		exit "${rc}"
	EOD
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"

	add_file_from_stdin_to_bsp_destination "/usr/lib/systemd/system/armbian-grub-dtb-overlays.path" <<- 'EOD'
		[Unit]
		Description=Watch armbianEnv.txt for device tree overlay changes

		[Path]
		PathModified=/boot/armbianEnv.txt
		Unit=armbian-grub-dtb-overlays.service

		[Install]
		WantedBy=multi-user.target
	EOD
	add_file_from_stdin_to_bsp_destination "/usr/lib/systemd/system/armbian-grub-dtb-overlays.service" <<- 'EOD'
		[Unit]
		Description=Apply device tree overlays to the GRUB DTB

		[Service]
		Type=oneshot
		ExecStart=/usr/lib/armbian/armbian-grub-dtb-overlays
	EOD

	postinst_functions+=(grub_with_dtb_bsp_cli_postinst_overlays)
}

# Copied inline into the bsp-cli postinst, so no return or local
function grub_with_dtb_bsp_cli_postinst_overlays() {
	if [[ "$1" == "configure" ]]; then
		grub_with_dtb_overlay_prefix="$(sed -n 's/^OVERLAY_PREFIX="\(.*\)"$/\1/p' /etc/armbian-grub-with-dtb 2> /dev/null)"
		if [[ -n "${grub_with_dtb_overlay_prefix}" ]]; then
			if [[ ! -f /boot/armbianEnv.txt ]]; then
				echo "# This board boots with GRUB. Only overlay_prefix, overlays and user_overlays are read from this file." > /boot/armbianEnv.txt
			fi
			if ! grep -q '^overlay_prefix=' /boot/armbianEnv.txt; then
				if [[ -n "$(tail -c 1 /boot/armbianEnv.txt)" ]]; then
					echo >> /boot/armbianEnv.txt
				fi
				echo "overlay_prefix=${grub_with_dtb_overlay_prefix}" >> /boot/armbianEnv.txt
			fi
			systemctl --no-reload enable armbian-grub-dtb-overlays.path > /dev/null 2>&1
			if [[ -d /run/systemd/system ]]; then
				systemctl daemon-reload
				systemctl start armbian-grub-dtb-overlays.path
				systemctl start --no-block armbian-grub-dtb-overlays.service
			fi
		fi
		unset grub_with_dtb_overlay_prefix
	fi
}

# `grub_early_config` and `grub_late_config` and `grub_pre_install` are hooks exposed by the `grub` extension

function grub_early_config__deploy_dtb_for_grub() {
	# @TODO: this could be deployed in the bsp-cli for consistency/updates?
	# Get rid of the original grub-mkconfig scripts and add our own.
	run_host_command_logged rm -fv "${MOUNT}"/etc/grub.d/{10_linux,20_linux_xen} # or maybe just remove their executable bit?
	run_host_command_logged cp -v "${SRC}/packages/blobs/grub/09_linux_with_dtb.sh" "${MOUNT}"/etc/grub.d/09_linux_with_dtb.sh
	run_host_command_logged chmod -v +x "${MOUNT}"/etc/grub.d/09_linux_with_dtb.sh
}

function grub_pre_install__force_run_kernel_hook_for_armbian_dtb() {
	# Run the kernel hook to deploy the DTB file to the boot partition.
	# This is done forcibly here during `grub_pre_install`, since the kernel hook is deployed in the bsp-cli package
	# which is only deployed after the linux-image package is installed and thus is not run.
	display_alert "Extension: ${EXTENSION}: Deploying DTB for GRUB for image build" "${BOARD}" "info"
	chroot_custom "${MOUNT}" 'for k in $(linux-version list); do /etc/kernel/postinst.d/armbian-grub-with-dtb "$k"; done'
}

function grub_late_config__check_dtb_in_grub_cfg() {
	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}: Debugging" "GRUB config and /boot contents" "info"
		run_tool_batcat "${MOUNT}/boot/grub/grub.cfg"
		run_host_command_logged ls -la --color=always "${MOUNT}"/boot
	fi

	if ! grep -q 'devicetree' "${MOUNT}/boot/grub/grub.cfg"; then
		display_alert "Extension: ${EXTENSION}: Sanity check failed" "GRUB DTB not found in grub.cfg; RELEASE=${RELEASE}" "warn"
	else
		display_alert "Extension: ${EXTENSION}: Sanity check passed" "GRUB DTB found in grub.cfg; RELEASE=${RELEASE}" "info"
	fi
	return 0
}
