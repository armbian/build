#!/usr/bin/env bash
function extension_finish_config__build_nvidia_kernel_module() {
	# Deny on minimal CLI images
	if [[ "${BUILD_MINIMAL}" == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}" "skip installation in minimal images" "warn"
		return 0
	fi

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping nVidia for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g MODULES_BLACKLIST="nouveau"
	declare -g INSTALL_HEADERS="yes"
	# pciutils (provides /usr/bin/lspci used by the runtime
	# armbian-nvidia-autodetect helper) is already in
	# config/cli/common/main/packages.additional and ships in every
	# non-minimal image. This extension early-returns on
	# BUILD_MINIMAL=yes, so we never reach this point without it.
	# No explicit install required here.
	# NVIDIA_DRIVER_VERSION is intentionally NOT defaulted here. The
	# post_install hook below asks apt (inside the chroot, after apt
	# sources are wired up) which nvidia-dkms-<N> is actually
	# available for the target distribution/release and picks the
	# highest one. Debian-style unversioned `nvidia-dkms` is the
	# fall-back when no numbered variants exist (Debian bookworm,
	# trixie). Set NVIDIA_DRIVER_VERSION via env or config to pin.
	display_alert "Forcing INSTALL_HEADERS=yes" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__build_nvidia_kernel_module() {
	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0

	# Pre-ship the modprobe blacklist BEFORE installing nvidia packages.
	# nvidia-dkms postinst triggers update-initramfs; with the file already
	# in /etc/modprobe.d/, the regenerated initramfs has the blacklist
	# baked in. Result: no spurious "nvidia: probe failed" lines on hosts
	# without an NVIDIA GPU during the first boot. The boot-time
	# armbian-nvidia-autodetect helper removes this file (and modprobes
	# nvidia_drm) when lspci does see [10de:].
	mkdir -p "${SDCARD}/etc/modprobe.d"
	cat <<- EOF > "${SDCARD}/etc/modprobe.d/armbian-nvidia-disabled.conf"
		# Installed by build/extensions/nvidia.sh.
		# Removed at boot by armbian-nvidia-autodetect when [10de:] is present.
		blacklist nvidia
		blacklist nvidia_drm
		blacklist nvidia_modeset
		blacklist nvidia_uvm
	EOF

	# Resolve which nvidia-dkms / nvidia-driver package(s) to install.
	# Three cases:
	#   1. Operator pinned NVIDIA_DRIVER_VERSION (env/config) → trust it.
	#   2. Auto-detect: highest `nvidia-dkms-<N>` in the chroot's apt
	#      index. This is the common Ubuntu shape — 535, 550, 560,
	#      580, … depending on release and snapshot.
	#   3. Fall through to the unversioned Debian metapackage
	#      `nvidia-dkms` when no numeric variants exist.
	# If none of the three resolve, skip with a warning rather than
	# blowing the build up with an opaque "package not found".
	local nvidia_dkms_pkg nvidia_driver_pkg
	if [[ -n "${NVIDIA_DRIVER_VERSION:-}" ]]; then
		nvidia_dkms_pkg="nvidia-dkms-${NVIDIA_DRIVER_VERSION}"
		nvidia_driver_pkg="nvidia-driver-${NVIDIA_DRIVER_VERSION}"
		display_alert "Using pinned NVIDIA_DRIVER_VERSION" "${NVIDIA_DRIVER_VERSION}" "info"
	else
		local latest pkgnames_raw sources_files sources_has_restricted apt_lists_sample
		# Refresh the chroot's apt indices first. The rootfs cache may
		# have been built before `restricted` was added to sources, or
		# the framework may not have run `apt-get update` since the
		# final sources.list was written. Without fresh indices,
		# `apt-cache pkgnames` returns nothing for restricted-only
		# packages (nvidia-dkms-*) even when sources.list lists the
		# component. Idempotent and quick if indices are already current.
		display_alert "Refreshing apt indices in chroot" "${EXTENSION}" "debug"
		chroot_sdcard "apt-get update -qq" || true

		# chroot_sdcard wraps the inner command with `bash -e -o
		# pipefail -c …`, so this pipeline returns 1 when grep finds
		# no numbered nvidia-dkms-N packages (Debian / fall-through
		# case). Under the framework's outer set -e the substitution
		# would abort the build before we get to test $latest, making
		# case-3 below unreachable. `|| true` keeps the substitution
		# successful with $latest empty so the fall-through fires.
		latest=$(chroot_sdcard "apt-cache pkgnames 'nvidia-dkms-' 2>/dev/null \
			| grep -E '^nvidia-dkms-[0-9]+\$' \
			| sed 's/nvidia-dkms-//' \
			| sort -nr | head -1 || true")
		if [[ -n "$latest" ]]; then
			NVIDIA_DRIVER_VERSION="$latest"
			nvidia_dkms_pkg="nvidia-dkms-${NVIDIA_DRIVER_VERSION}"
			nvidia_driver_pkg="nvidia-driver-${NVIDIA_DRIVER_VERSION}"
			display_alert "Auto-detected nvidia-dkms for ${DISTRIBUTION}/${RELEASE}" "${NVIDIA_DRIVER_VERSION}" "info"
		elif chroot_sdcard "apt-cache pkgnames nvidia-dkms 2>/dev/null | grep -qx nvidia-dkms"; then
			nvidia_dkms_pkg="nvidia-dkms"
			nvidia_driver_pkg="nvidia-driver"
			display_alert "Using unversioned nvidia-dkms metapackage" "${DISTRIBUTION}/${RELEASE}" "info"
		else
			# Detection failed. Dump enough state to diagnose without
			# needing to re-enter the chroot manually.
			# Every chroot_sdcard pipeline below ends in `|| true`. The
			# inner bash runs with -e -o pipefail; grep / find return 1
			# when nothing matches, which pipefail propagates and would
			# abort the outer build in a way that triggers bash's
			# pop_var_context warning instead of just reporting the
			# diagnostic.
			pkgnames_raw=$(chroot_sdcard "apt-cache pkgnames 2>/dev/null | grep -c '^nvidia' || true")
			sources_files=$(chroot_sdcard "ls /etc/apt/sources.list.d/ 2>/dev/null | tr '\n' ' ' || true")
			sources_has_restricted=$(chroot_sdcard "grep -lF restricted /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null | tr '\n' ' ' || true")
			apt_lists_sample=$(chroot_sdcard "ls /var/lib/apt/lists/ 2>/dev/null | grep -E 'restricted|multiverse' | head -5 | tr '\n' ' ' || true")
			display_alert "nvidia-dkms detection failed" "${DISTRIBUTION}/${RELEASE}" "warn"
			display_alert "  apt-cache pkgnames | grep ^nvidia count" "${pkgnames_raw}" "warn"
			display_alert "  sources.list.d entries" "${sources_files:-<none>}" "warn"
			display_alert "  files mentioning 'restricted'" "${sources_has_restricted:-<none>}" "warn"
			display_alert "  apt/lists entries containing restricted/multiverse" "${apt_lists_sample:-<none — apt-get update may not have refreshed indices>}" "warn"
			display_alert "No nvidia-dkms package in ${DISTRIBUTION}/${RELEASE} apt sources" "skipping nVidia install" "warn"
			return 0
		fi
	fi

	display_alert "Install nVidia packages, build kernel module in chroot" "${EXTENSION} (${nvidia_dkms_pkg})" "info"
	# chroot_sdcard_apt_get_install() is in lib/logging/runners.sh which handles "running" of stuff nicely.
	# chroot_sdcard_apt_get_install() -> chroot_sdcard_apt_get() -> chroot_sdcard() -> run_host_command_logged_raw()
	# it handles bash-specific quoting issues, apt proxies, logging, and errors.
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/nvidia/*/build/make.log")
	chroot_sdcard_apt_get_install "${nvidia_dkms_pkg}" "${nvidia_driver_pkg}"
}

# Hook docs (lib/functions/rootfs/distro-agnostic.sh): post_install_kernel_debs
# explicitly fires BEFORE the BSP is installed. Anything we write under
# /usr/lib/armbian/ or /etc/systemd/system/ there gets clobbered by the
# BSP install or by later rootfs sweeps. post_family_tweaks fires AFTER
# `install_artifact_deb_chroot "armbian-bsp-cli"` (around line 454), so
# this is the right hook for writing extension-owned auxiliary files
# into the chroot's final filesystem.
function post_family_tweaks__build_nvidia_kernel_module_autodetect() {
	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0
	install_armbian_nvidia_autodetect_helper
}

# -----------------------------------------------------------------------------
# Runtime auto-disable of the driver on hosts without NVIDIA hardware.
#
# Replaces a dmesg-grep one-liner that used to live in
# packages/bsp/common/usr/lib/armbian/armbian-firstrun. The old approach was
# unreliable for two reasons:
#   1. It looked for "No NVIDIA GPU found" in dmesg — that line is only
#      printed if the driver actually attempted to bind and failed, and is
#      already rotated out of the ring buffer on many boots.
#   2. It purged a hardcoded version (nvidia-dkms-510) — wrong on every
#      distro/release that ships a different driver branch, and especially
#      wrong now that the install path auto-picks the highest available.
#
# This installs a small detector + systemd one-shot that:
#   - probes the PCI bus directly (lspci, vendor 0x10de) — works regardless
#     of whether the driver loaded,
#   - blacklists nvidia / nvidia_drm / nvidia_modeset / nvidia_uvm via
#     /etc/modprobe.d so they don't load on the next boot,
#   - dpkg-query's the actually-installed nvidia-dkms-* / nvidia-driver-* /
#     nvidia-settings / nvidia-common packages (no hardcoded version) and
#     apt-purges them.
# -----------------------------------------------------------------------------
function install_armbian_nvidia_autodetect_helper() {
	display_alert "Installing runtime NVIDIA hardware detector" "${EXTENSION}" "info"

	mkdir -p "${SDCARD}/usr/lib/armbian" "${SDCARD}/etc/systemd/system"

	cat <<- 'AUTODETECT_SH' > "${SDCARD}/usr/lib/armbian/armbian-nvidia-autodetect"
		#!/bin/sh
		# armbian-nvidia-autodetect — installed by build/extensions/nvidia.sh.
		#
		# On hosts WITH an NVIDIA GPU (PCI vendor 10de): no-op.
		# On hosts WITHOUT one: blacklist the modules and purge the nvidia
		# packages so DKMS doesn't keep rebuilding the kernel module on
		# every kernel update.
		#
		# Detection is via lspci (queries the PCI bus directly). Earlier
		# attempts used `dmesg | grep "No NVIDIA GPU found"` which only
		# fires if the driver bound far enough to print that line, and
		# falls off the ring buffer.

		set -e

		# Need lspci. It's part of pciutils — present on every desktop
		# image, but be defensive on hand-built minimal flavours.
		if ! command -v lspci > /dev/null 2>&1; then
			exit 0
		fi

		# NVIDIA PCI vendor ID is 0x10de. Match the literal "[10de:" in
		# `lspci -nn` output so non-VGA NVIDIA devices (Tegra USB-C,
		# audio over HDMI, etc.) also count.
		if lspci -nn 2>/dev/null | grep -qiE '\[10de:'; then
			# Hardware is present. The build framework ships a default
			# /etc/modprobe.d/armbian-nvidia-disabled.conf so initrd udev
			# doesn't try to load nvidia* on no-GPU hosts. Now that we've
			# confirmed there IS a GPU, clear the file and modprobe so
			# display-manager (we are Before= it) starts with the driver
			# loaded. The rootfs deletion self-heals initramfs on the
			# next kernel upgrade — until then, initrd stays stale but
			# this runtime modprobe covers the gap each boot.
			#
			# rm -f is idempotent. modprobe nvidia_drm with modeset=1
			# pulls nvidia + nvidia_modeset via dependencies and gives
			# Wayland-friendly KMS in one shot. || true on the modprobe
			# in case the package was previously purged and isn't
			# installed - the operator handles re-install separately.
			if [ -f /etc/modprobe.d/armbian-nvidia-disabled.conf ]; then
				rm -f /etc/modprobe.d/armbian-nvidia-disabled.conf
				echo "armbian-nvidia-autodetect: NVIDIA hardware detected; cleared modprobe blacklist" | systemd-cat -t armbian-nvidia-autodetect 2>/dev/null || true
			fi
			modprobe nvidia_drm modeset=1 2>/dev/null || true
			exit 0
		fi

		# No NVIDIA hardware. Belt and suspenders:
		#   1. modprobe.d blacklist — takes effect on the next boot and
		#      is idempotent if we get killed mid-purge.
		#   2. apt purge — removes the package set so DKMS doesn't burn
		#      cycles rebuilding modules that will never load.
		cat > /etc/modprobe.d/armbian-nvidia-disabled.conf <<-EOF
			# Installed by armbian-nvidia-autodetect: no NVIDIA GPU on this host.
			# Delete this file to re-enable the driver.
			blacklist nvidia
			blacklist nvidia_drm
			blacklist nvidia_modeset
			blacklist nvidia_uvm
		EOF

		# dpkg-query the package set actually installed (no hardcoded
		# version — varies per distro / extension config). Returns
		# empty on a second run, which makes the purge a no-op.
		# Glob 'nvidia-dkms-*' requires the trailing dash so it won't
		# match the bare 'nvidia-dkms' / 'nvidia-driver' metapackages
		# Debian ships (and which the install branch above can pick
		# under case-3). List those exact names alongside the globs
		# so the purge covers both shapes.
		NVIDIA_PKGS=$(dpkg-query -W -f='${binary:Package}\n' \
			'nvidia-dkms-*' 'nvidia-driver-*' \
			'nvidia-dkms'   'nvidia-driver'   \
			'nvidia-settings' 'nvidia-common' 2>/dev/null | tr '\n' ' ')
		if [ -n "$NVIDIA_PKGS" ]; then
			DEBIAN_FRONTEND=noninteractive apt-get -y -qq purge $NVIDIA_PKGS >/dev/null 2>&1 || true
			DEBIAN_FRONTEND=noninteractive apt-get -y -qq autoremove --purge >/dev/null 2>&1 || true
		fi
	AUTODETECT_SH
	chmod 0755 "${SDCARD}/usr/lib/armbian/armbian-nvidia-autodetect"

	cat <<- 'AUTODETECT_SERVICE' > "${SDCARD}/etc/systemd/system/armbian-nvidia-autodetect.service"
		[Unit]
		Description=Detect NVIDIA hardware; disable driver if absent
		Documentation=https://github.com/armbian/build/blob/main/extensions/nvidia.sh
		# Run BEFORE anything that might try to use the GPU (display
		# manager, console framebuffer init). After local fs so the
		# script's writes and dpkg state are available.
		After=local-fs.target
		Before=display-manager.service graphical.target

		[Service]
		Type=oneshot
		ExecStart=/usr/lib/armbian/armbian-nvidia-autodetect
		# Stay activated so the unit shows green in `systemctl status`
		# after a successful run — without this the unit would always
		# read as inactive (dead).
		RemainAfterExit=yes

		[Install]
		WantedBy=multi-user.target
	AUTODETECT_SERVICE

	# Enable the unit so it fires at every boot. Cheap when NVIDIA is
	# present (early exit on the lspci check) and idempotent when not
	# (apt-purge is a no-op on a system where the packages are already
	# gone). Running every boot means hot-pluggable scenarios (eGPU,
	# Thunderbolt) get re-evaluated.
	chroot_sdcard "systemctl enable armbian-nvidia-autodetect.service" || \
		display_alert "Could not enable armbian-nvidia-autodetect.service in chroot" "${EXTENSION}" "warn"
}
