#!/usr/bin/env bash
# @description Adds AIC8800D80 Wi-Fi 6 + Bluetooth 5 (SDIO) support for Sophgo SG200x / Milk-V Duo S boards. Copies the SDIO driver from a pinned `radxa-pkg/aic8800` commit into the kernel tree, applies the SDIO part of its Debian patch series, and builds it as in-tree modules. Also configures modprobe ordering and a Bluetooth attach service.

#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
# Extension: sophgo-sg200x-aic8800
#
# The AIC8800D80 sits on sdhci1. The device tree powers it through wifi_pwrseq.
#
# The radxa-aic8800 extension installs the same driver as a DKMS deb. This
# extension builds it in the kernel tree instead: no DKMS run under qemu and no
# headers package on the target.
#
# The copy runs from custom_kernel_config, not kernel_copy_extra_sources:
# patching resets the tree and removes untracked files.
#

# TODO: switch to radxa-pkg/aic8800 when the stable MAC fix (radxa-pkg/aic8800#121)
# is merged.
declare -g AIC8800_REPO="${AIC8800_REPO:-https://github.com/lukaszsobala/aic8800}"
# Pinned; a branch ref breaks kernel build caching.
declare -g AIC8800_REF="${AIC8800_REF:-commit:12f527d090c8aac0f27f0a74f267567fd5ca1f14}"

# armbian-firmware provides the blobs. The driver appends the chip directory
# (/aic8800D80) to this base. Override at runtime with:
#   modprobe aic8800_bsp aic_fw_path=/some/other/dir
declare -g AIC8800_FW_BASE="/lib/firmware/aic8800/SDIO"
declare -g AIC8800_FW_DIR="${AIC8800_FW_BASE}/aic8800D80"

function post_family_config__sophgo_sg200x_aic8800_src_dir() {
	declare -g AIC8800_SRC_DIR="${SRC}/cache/sources/aic8800-radxa/${AIC8800_REF#*:}"
}

function custom_kernel_config__sophgo_sg200x_aic8800_modules() {
	# Rebuild the kernel when the driver revision or the firmware path changes.
	# The path is compiled into aic8800_bsp.
	kernel_config_modifying_hashes+=("sophgo_sg200x_aic8800=${AIC8800_REPO}@${AIC8800_REF}")
	kernel_config_modifying_hashes+=("sophgo_sg200x_aic8800_fw_base=${AIC8800_FW_BASE}")

	# Also called for version calculation, with no kernel tree.
	[[ ! -f .config ]] && return 0

	# Fetch only here: post_family_config runs for config dumps too, often in
	# parallel, and a fetch there races on the global git config.
	declare kernel_cwd="${PWD}"
	fetch_from_repo "${AIC8800_REPO}" "aic8800-radxa" "${AIC8800_REF}" "yes"
	cd "${kernel_cwd}" || exit_with_error "SG200x AIC8800" "could not return to ${kernel_cwd}"

	declare upstream_dir="src/SDIO/driver_fw/driver/aic8800"
	declare wireless_dir="${kernel_work_dir}/drivers/net/wireless"
	declare driver_dir="${wireless_dir}/aic8800"

	display_alert "SG200x AIC8800" "adding driver to kernel tree" "info"

	run_host_command_logged rm -rf "${driver_dir}"
	run_host_command_logged mkdir -p "${driver_dir}"
	run_host_command_logged cp -a "${AIC8800_SRC_DIR}/${upstream_dir}/." "${driver_dir}/"

	# The Debian series patches SDIO, USB and PCIe together. Apply the SDIO part
	# only, in series order, to the copy in the kernel tree.
	declare patch_name sdio_part
	while read -r patch_name || [[ -n "${patch_name}" ]]; do
		[[ -z "${patch_name}" || "${patch_name}" == \#* ]] && continue
		sdio_part="$(filterdiff -p1 -i "${upstream_dir}/*" "${AIC8800_SRC_DIR}/debian/patches/${patch_name}")"
		[[ -z "${sdio_part}" ]] && continue
		display_alert "SG200x AIC8800" "applying ${patch_name}" "info"
		# -p6: a/src/SDIO/driver_fw/driver/aic8800/<file>
		patch --batch --forward --no-backup-if-mismatch -p6 -d "${driver_dir}" <<< "${sdio_part}" ||
			exit_with_error "AIC8800 patch did not apply" "${patch_name}"
	done < "${AIC8800_SRC_DIR}/debian/patches/series"

	# aic8800_bsp/Makefile sets CONFIG_AIC_FW_PATH itself and overrides Kconfig
	# for its own objects. Set both to the same value.
	sed -i "s|^CONFIG_AIC_FW_PATH = .*|CONFIG_AIC_FW_PATH = \"${AIC8800_FW_BASE}\"|" \
		"${driver_dir}/aic8800_bsp/Makefile"
	grep -qF "CONFIG_AIC_FW_PATH = \"${AIC8800_FW_BASE}\"" "${driver_dir}/aic8800_bsp/Makefile" ||
		exit_with_error "AIC8800 firmware path not set in the driver Makefile" "${AIC8800_FW_BASE}"

	# The preallocated RX buffers stay allocated. The board has 512MB of RAM.
	sed -i 's|^export CONFIG_PREALLOC_RX_SKB = y|export CONFIG_PREALLOC_RX_SKB = n|' "${driver_dir}/Makefile"
	grep -qx 'export CONFIG_PREALLOC_RX_SKB = n' "${driver_dir}/Makefile" ||
		exit_with_error "AIC8800 RX preallocation not disabled" "${driver_dir}/Makefile"

	if ! grep -q "aic8800/Kconfig" "${wireless_dir}/Kconfig"; then
		sed -i 's|^source "drivers/net/wireless/admtek/Kconfig"|source "drivers/net/wireless/aic8800/Kconfig"\n&|' \
			"${wireless_dir}/Kconfig"
	fi
	if ! grep -q "aic8800/" "${wireless_dir}/Makefile"; then
		echo 'obj-$(CONFIG_AIC_WLAN_SUPPORT) += aic8800/' >> "${wireless_dir}/Makefile"
	fi

	# CONFIG_AIC_WLAN_SUPPORT only makes the build descend into aic8800/. The
	# Makefile there builds the three modules as =m.
	kernel_config_set_y CONFIG_AIC_WLAN_SUPPORT
	kernel_config_set_m CONFIG_AIC8800_WLAN_SUPPORT
	kernel_config_set_m CONFIG_AIC8800_BTLPM_SUPPORT
	kernel_config_set_string CONFIG_AIC_FW_PATH "${AIC8800_FW_BASE}"

	kernel_config_set_m CONFIG_CFG80211
}

# armbian-firmware installs the blobs before this hook runs. Check them.
function post_family_tweaks__sophgo_sg200x_aic8800_firmware() {
	declare fw_dir="${SDCARD}${AIC8800_FW_DIR}"

	display_alert "SG200x AIC8800" "checking firmware from armbian-firmware" "info"

	# aic8800_bsp uploads the first four, aic8800_fdrv reads the userconfig.
	# lmacfw_rf is for RF test mode only.
	declare fw_file
	for fw_file in fw_patch_table_8800d80_u02.bin fw_adid_8800d80_u02.bin \
		fw_patch_8800d80_u02.bin fmacfw_8800d80_u02.bin aic_userconfig_8800d80.txt; do
		[[ -f "${fw_dir}/${fw_file}" ]] ||
			exit_with_error "AIC8800 firmware missing from the rootfs" "${fw_dir}/${fw_file}"
	done

	# The firmware path is compiled into the modules. The installed kernel must match.
	declare kernel_config
	for kernel_config in "${SDCARD}"/boot/config-*; do
		[[ -f "${kernel_config}" ]] || continue
		grep -qxF "CONFIG_AIC_FW_PATH=\"${AIC8800_FW_BASE}\"" "${kernel_config}" ||
			exit_with_error "AIC8800 kernel was built for a different firmware path" \
				"$(grep '^CONFIG_AIC_FW_PATH=' "${kernel_config}") in $(basename "${kernel_config}"), wanted ${AIC8800_FW_BASE}"
	done
}

# Write to ${SDCARD} here, not in pre_umount_final_image: the rootfs is already
# copied to the image by then.
function post_family_tweaks__sophgo_sg200x_aic8800_modprobe() {
	display_alert "SG200x AIC8800" "configuring module load order" "info"

	mkdir -p "${SDCARD}/etc/modprobe.d"
	cat <<- 'EOF2' > "${SDCARD}/etc/modprobe.d/aic8800.conf"
		# aic8800_bsp uploads the firmware. Load it first.
		softdep aic8800_fdrv pre: aic8800_bsp
		softdep aic8800_btlpm pre: aic8800_bsp
	EOF2

	mkdir -p "${SDCARD}/etc/modules-load.d"
	cat <<- 'EOF2' > "${SDCARD}/etc/modules-load.d/aic8800.conf"
		# Bluetooth works without aic8800_btlpm. It only adds an rfkill.
		aic8800_bsp
		aic8800_fdrv
	EOF2
}

# Bluetooth is an HCI H4 controller on uart4. aic8800_bsp uploads its patch.
# The BSP package installs the attach script and unit, so upgrades reach them.
function post_family_tweaks_bsp__sophgo_sg200x_aic8800_bluetooth() {
	display_alert "SG200x AIC8800" "installing Bluetooth attach service" "info"

	run_host_command_logged install -d -m 0755 "${destination}/usr/bin"
	run_host_command_logged install -m 0755 \
		"${SRC}/packages/bsp/sophgo-sg200x/usr/bin/aic8800-bluetooth" \
		"${destination}/usr/bin/aic8800-bluetooth"

	run_host_command_logged install -d -m 0755 "${destination}/usr/lib/systemd/system"
	run_host_command_logged install -m 0644 \
		"${SRC}/packages/bsp/sophgo-sg200x/usr/lib/systemd/system/aic8800-bluetooth.service" \
		"${destination}/usr/lib/systemd/system/aic8800-bluetooth.service"
}

function post_family_tweaks__sophgo_sg200x_aic8800_bluetooth_enable() {
	display_alert "SG200x AIC8800" "enabling Bluetooth attach service" "info"
	chroot_sdcard systemctl --no-reload enable aic8800-bluetooth.service
}
