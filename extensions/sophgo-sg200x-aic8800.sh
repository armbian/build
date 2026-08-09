#!/usr/bin/env bash
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
# AIC8800D80 Wi-Fi 6 + Bluetooth 5 support for Sophgo SG200x boards (Milk-V
# Duo S), where the chip hangs off SDIO (sdhci1) and its enable line is a pin
# that has to be poked directly - there is no mainline driver.
#
# Named for the board family, not the chip: AICSemi make the AIC8800, and the
# tree already has two other extensions for it. Both of those install prebuilt
# DKMS debs from third-party release pages - brostrend-aic8800-dkms.sh from
# Shadowrom2020/aic8800-dkms, radxa-aic8800.sh from radxa-pkg/aic8800, the latter
# skipping itself on kernels 7.2 and newer. Neither can serve this board, so this
# extension takes the other route: the vendor driver out of Milk-V's
# duo-buildroot-sdk-v2, as cleaned up for modern kernels by queenkjuul, copied
# into the kernel tree and built as ordinary in-tree modules. That is much
# cheaper than DKMS under qemu, needs no headers package on the target, and is
# what makes 7.2 work.
#
# What is not board-specific is shared rather than duplicated: the two build
# fixes live in patch/misc/aic8800/ next to the other driver patches. The
# Bluetooth attach script and unit are not shared - they resolve the UART by
# hardware address, which only this board needs - so they sit with the rest of
# the family's BSP files in packages/bsp/sophgo-sg200x/ rather than in the
# framework-wide packages/bsp/aic8800/ next to the aic-bluetooth pair.
#
# The copy happens from custom_kernel_config, not kernel_copy_extra_sources:
# patching does a git reset --hard plus a clean of untracked files, so anything
# staged earlier than that gets wiped.
#

declare -g AIC8800_REPO="https://github.com/queenkjuul/aic8800-milkv-duos"
# Pinned; a mutable branch ref would break kernel build caching.
declare -g AIC8800_REF="commit:ccf8fd059f70384fae4878c1048603510c2df700"

# Firmware comes from armbian-firmware, which every image installs; this repo
# ships none. It used to carry Milk-V's own aicsemi build, a different one to
# upstream's - but upstream's drives this chip just as well, so the blobs are gone.
#
# One variable because the path reaches the modules two different ways; see
# custom_kernel_config below. It is also overridable at runtime, which is the easy
# way to test a different firmware set without rebuilding:
#   modprobe aic8800_bsp aic_fw_path=/some/other/dir
declare -g AIC8800_FW_DIR="/lib/firmware/aic8800/SDIO/aic8800D80"

function post_family_config__sophgo_sg200x_aic8800_fetch() {
	# The source dir is a deterministic path off the pinned ref; always declare it.
	declare -g AIC8800_SRC_DIR="${SRC}/cache/sources/aic8800-milkv-duos/${AIC8800_REF#*:}"

	# Don't fetch during config-dump / version calculation. post_family_config
	# also runs under `config-dump-json` (CONFIG_DEFS_ONLY=yes), which the
	# inventory runs in parallel for every board×branch; a real git fetch here
	# has no kernel tree to feed and races on the global git config
	# (`git config --global --add safe.directory ...` -> exit 128), which then
	# breaks the whole inventory. The driver is fetched for real when the kernel
	# builds (custom_kernel_config, guarded on a present .config).
	[[ "${CONFIG_DEFS_ONLY}" == "yes" ]] && return 0

	fetch_from_repo "${AIC8800_REPO}" "aic8800-milkv-duos" "${AIC8800_REF}" "yes"
}

function custom_kernel_config__sophgo_sg200x_aic8800_modules() {
	declare -a patches=()
	mapfile -t patches < <(find "${SRC}/patch/misc/aic8800" -maxdepth 1 -name '*.patch' | sort)

	# Rebuild the kernel when the driver revision or the patches change.
	kernel_config_modifying_hashes+=("sophgo_sg200x_aic8800=${AIC8800_REF}")
	kernel_config_modifying_hashes+=("sophgo_sg200x_aic8800_patches=$(cat /dev/null "${patches[@]}" | sha256sum | cut -d' ' -f1)")

	# ...and when the firmware path changes, because it is compiled into the modules
	# (see below). It has to be hashed here explicitly: the kernel_config_set_* helpers
	# below do add their arguments to this array, but they also run scripts/config, so
	# they only work in the phase that has a .config - never the phase that computes the
	# artifact version. Leaving it out means the deb keeps its old name, the cached one
	# built for the previous path is reused, and the driver spends the boot looking for
	# firmware in a directory the rootfs no longer has.
	kernel_config_modifying_hashes+=("sophgo_sg200x_aic8800_fw_dir=${AIC8800_FW_DIR}")

	# Also called during config dumping / version calculation, with no kernel tree.
	[[ ! -f .config ]] && return 0

	declare wireless_dir="${kernel_work_dir}/drivers/net/wireless"
	declare driver_dir="${wireless_dir}/aicsemi"

	display_alert "SG200x AIC8800" "adding driver to kernel tree" "info"

	run_host_command_logged rm -rf "${driver_dir}"
	run_host_command_logged mkdir -p "${driver_dir}"
	run_host_command_logged cp -a "${AIC8800_SRC_DIR}/aicsemi/." "${driver_dir}/"

	# The vendor sources are not maintained against new kernels; the patches
	# here are what keeps them building. They are applied to the copy in the
	# kernel tree, not to the shared cache/sources checkout.
	declare patch_file
	for patch_file in "${patches[@]}"; do
		display_alert "SG200x AIC8800" "applying $(basename "${patch_file}")" "info"
		run_host_command_logged patch --batch -p1 -d "${kernel_work_dir}" "<" "${patch_file}" ||
			exit_with_error "AIC8800 patch did not apply" "$(basename "${patch_file}")"
	done

	# The firmware path reaches the two modules by two different routes:
	# aic8800_bsp/Makefile assigns CONFIG_AIC_FW_PATH itself (with =, not ?=), so it
	# overrides the Kconfig value for its own objects, while aic8800_fdrv/Makefile
	# takes whatever .config says. Set both, or the modules end up looking in two
	# different directories.
	sed -i "s|^CONFIG_AIC_FW_PATH = .*|CONFIG_AIC_FW_PATH = \"${AIC8800_FW_DIR}\"|" \
		"${driver_dir}/aic8800/aic8800_bsp/Makefile"
	grep -qF "CONFIG_AIC_FW_PATH = \"${AIC8800_FW_DIR}\"" "${driver_dir}/aic8800/aic8800_bsp/Makefile" ||
		exit_with_error "AIC8800 firmware path not set in the vendor Makefile" "${AIC8800_FW_DIR}"

	# Hook the new vendor directory into the wireless Kconfig and Makefile.
	if ! grep -q "aicsemi/Kconfig" "${wireless_dir}/Kconfig"; then
		sed -i 's|^source "drivers/net/wireless/admtek/Kconfig"|source "drivers/net/wireless/aicsemi/Kconfig"\n&|' \
			"${wireless_dir}/Kconfig"
	fi
	if ! grep -q "aicsemi/" "${wireless_dir}/Makefile"; then
		echo 'obj-$(CONFIG_WLAN_VENDOR_AICSEMI) += aicsemi/' >> "${wireless_dir}/Makefile"
	fi

	# CONFIG_AIC8800 is a bool that only makes the build descend into aic8800/;
	# the Makefile in there forces the three actual modules to =m.
	kernel_config_set_y CONFIG_WLAN_VENDOR_AICSEMI
	kernel_config_set_y CONFIG_AIC8800
	kernel_config_set_string CONFIG_AIC_FW_PATH "${AIC8800_FW_DIR}"

	# cfg80211 has to be reachable from the driver.
	kernel_config_set_m CONFIG_CFG80211
}

# armbian-firmware provides the blobs and is installed well before this hook runs
# (lib/functions/rootfs/distro-agnostic.sh). Nothing to do here but make sure they
# are actually present.
function post_family_tweaks__sophgo_sg200x_aic8800_firmware() {
	declare fw_dir="${SDCARD}${AIC8800_FW_DIR}"

	display_alert "SG200x AIC8800" "checking firmware from armbian-firmware" "info"

	# aic8800_bsp uploads the first four - fw_adid/fw_patch/fw_patch_table are the
	# Bluetooth patch it pushes over SDIO, fmacfw is the Wi-Fi MAC firmware - and
	# aic8800_fdrv reads the userconfig. lmacfw_rf is deliberately not checked: it
	# is only reachable by putting the bsp into RF test mode via its cpmode sysfs
	# attribute, so a missing one does not stop the board working.
	declare fw_file
	for fw_file in fw_patch_table_8800d80_u02.bin fw_adid_8800d80_u02.bin \
		fw_patch_8800d80_u02.bin fmacfw_8800d80_u02.bin aic_userconfig_8800d80.txt; do
		[[ -f "${fw_dir}/${fw_file}" ]] ||
			exit_with_error "AIC8800 firmware missing from the rootfs" "${fw_dir}/${fw_file}"
	done

	# Blobs in the right place are only half of it: the path is compiled into the
	# modules, so the kernel package installed here has to agree with the one they were
	# built for.
	declare kernel_config
	for kernel_config in "${SDCARD}"/boot/config-*; do
		[[ -f "${kernel_config}" ]] || continue
		grep -qxF "CONFIG_AIC_FW_PATH=\"${AIC8800_FW_DIR}\"" "${kernel_config}" ||
			exit_with_error "AIC8800 kernel was built for a different firmware path" \
				"$(grep '^CONFIG_AIC_FW_PATH=' "${kernel_config}") in $(basename "${kernel_config}"), wanted ${AIC8800_FW_DIR}"
	done
}

# Anything written into the rootfs has to be written from here or earlier, not from
# pre_umount_final_image: ${SDCARD} is rsynced into the mounted image early in
# rootfs-to-image.sh, and update_initramfs follows immediately. Writes from the
# later hook still "succeed" - ${SDCARD} is a live host path - but never reach the
# image.
function post_family_tweaks__sophgo_sg200x_aic8800_modprobe() {
	display_alert "SG200x AIC8800" "configuring module load order" "info"

	mkdir -p "${SDCARD}/etc/modprobe.d"
	cat <<- 'EOF' > "${SDCARD}/etc/modprobe.d/aic8800.conf"
		# aic8800_bsp brings the chip out of reset and uploads firmware; the
		# wifi and bluetooth drivers are useless until it has run.
		softdep aic8800_fdrv pre: aic8800_bsp
		softdep aic8800_btlpm pre: aic8800_bsp
	EOF

	mkdir -p "${SDCARD}/etc/modules-load.d"
	cat <<- 'EOF' > "${SDCARD}/etc/modules-load.d/aic8800.conf"
		# aic8800_btlpm is deliberately not here: it only adds an rfkill for
		# gating the BT subsystem, and the controller is already live once the
		# bsp has run - Bluetooth works without it.
		aic8800_bsp
		aic8800_fdrv
	EOF
}

# The chip's Bluetooth side is a plain HCI H4 controller on uart4, already holding
# the patch aic8800_bsp uploaded over SDIO - so all it needs is an hciattach at the
# baud rate the patch table announces. These go into the BSP package rather than
# straight into ${SDCARD} because they are executable assets: dpkg then owns them
# and an armbian-bsp-cli upgrade carries fixes to installed systems.
#
# packages/bsp/sophgo-sg200x is hashed into the bsp-cli version by the family
# config, so edits to either file below give the deb a new version; see the
# BSP_CLI_EXTRA_HASH_DIRS comment in sophgo-sg200x_common.inc.
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

# The chip has nothing in its efuse, so the driver falls back to a compiled-in MAC
# address with two random bytes on the end and wlan0 comes up different on every
# boot. The helper that fixes it belongs to the SoC, not to this chip - the
# ethernet has the same problem - so it is installed by
# sophgo-sg200x_common.inc and only the rule is added here. Both land in the same
# armbian-bsp-cli, so there is no ordering or packaging dependency between them.
function post_family_tweaks_bsp__sophgo_sg200x_aic8800_stable_mac() {
	display_alert "SG200x AIC8800" "installing stable Wi-Fi MAC address rule" "info"

	run_host_command_logged install -d -m 0755 "${destination}/etc/udev/rules.d"
	run_host_command_logged install -m 0644 \
		"${SRC}/packages/bsp/sophgo-sg200x/etc/udev/rules.d/70-sg200x-stable-mac-wifi.rules" \
		"${destination}/etc/udev/rules.d/70-sg200x-stable-mac-wifi.rules"
}

function post_family_tweaks__sophgo_sg200x_aic8800_bluetooth_enable() {
	display_alert "SG200x AIC8800" "enabling Bluetooth attach service" "info"
	chroot_sdcard systemctl --no-reload enable aic8800-bluetooth.service
}
