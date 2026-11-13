#!/usr/bin/env bash
# @description Installs the NVIDIA proprietary driver and builds its kernel module via DKMS, blacklisting `nouveau`. Auto-detects the highest `nvidia-dkms-<N>` in the chroot's apt index (or uses `NVIDIA_DRIVER_VERSION`/Debian `nvidia-kernel-dkms`), forces `INSTALL_HEADERS=yes`, and ships an `armbian-nvidia-autodetect` service: on GPU-less hosts it blacklists the driver at boot and removes it at the next shutdown. Skipped on minimal images and on kernels without a working headers package.

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
	# highest one. Debian `nvidia-kernel-dkms` is the fall-back when no
	# numbered variants exist (Debian bookworm, trixie). Set NVIDIA_DRIVER_VERSION via env or config to pin.
	display_alert "Forcing INSTALL_HEADERS=yes" "${EXTENSION}" "debug"
}

# Runs after the build enables the Armbian repository (image-late): nvidia-open
# comes from it. Earlier hooks see only the distribution repositories.
function post_repo_customize_image__build_nvidia_kernel_module() {
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
	# Four cases:
	#   1. Operator pinned NVIDIA_DRIVER_VERSION (env/config) → trust it.
	#   2. `nvidia-open`: the latest driver from the NVIDIA repository,
	#      mirrored into the Armbian repository (armbian/external).
	#   3. Auto-detect: highest `nvidia-dkms-<N>` in the chroot's apt
	#      index. This is the common Ubuntu shape — 535, 550, 560,
	#      580, … depending on release and snapshot.
	#   4. Fall through to Debian `nvidia-kernel-dkms` when no numeric
	#      variants exist.
	# If none of them resolve, skip with a warning rather than
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
		# the cases below unreachable. `|| true` keeps the substitution
		# successful with $latest empty so the fall-through fires.
		latest=$(chroot_sdcard "apt-cache pkgnames 'nvidia-dkms-' 2>/dev/null \
			| grep -E '^nvidia-dkms-[0-9]+\$' \
			| sed 's/nvidia-dkms-//' \
			| sort -nr | head -1 || true")
		if chroot_sdcard "apt-cache pkgnames nvidia-open 2>/dev/null | grep -qx nvidia-open"; then
			# One package pulls the driver and the open kernel module.
			# Turing and newer only. Older GPUs are not supported: the user
			# installs a legacy driver (board-instructions/uefi-x86.md).
			nvidia_dkms_pkg="nvidia-open"
			display_alert "Using nvidia-open from the Armbian repository" "${DISTRIBUTION}/${RELEASE}" "info"
		elif [[ -n "$latest" ]]; then
			NVIDIA_DRIVER_VERSION="$latest"
			nvidia_dkms_pkg="nvidia-dkms-${NVIDIA_DRIVER_VERSION}"
			nvidia_driver_pkg="nvidia-driver-${NVIDIA_DRIVER_VERSION}"
			display_alert "Auto-detected nvidia-dkms for ${DISTRIBUTION}/${RELEASE}" "${NVIDIA_DRIVER_VERSION}" "info"
		elif chroot_sdcard "apt-cache pkgnames nvidia-kernel-dkms 2>/dev/null | grep -qx nvidia-kernel-dkms"; then
			# Debian (non-free): one driver branch per release, no numbered packages.
			nvidia_dkms_pkg="nvidia-kernel-dkms"
			nvidia_driver_pkg="nvidia-driver"
			display_alert "Using Debian nvidia-kernel-dkms" "${DISTRIBUTION}/${RELEASE}" "info"
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
	chroot_sdcard_apt_get_install "${nvidia_dkms_pkg}" ${nvidia_driver_pkg:+"${nvidia_driver_pkg}"}
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
# Runtime: the driver is installed by default. On a host without NVIDIA
# hardware, the boot only blacklists the modules. The package removal takes
# about a minute, so it runs at the next shutdown or reboot, not at boot.
# A live system (boot=live) keeps the packages: the removal frees nothing there.
# -----------------------------------------------------------------------------
function install_armbian_nvidia_autodetect_helper() {
	display_alert "Installing runtime NVIDIA hardware detector" "${EXTENSION}" "info"

	mkdir -p "${SDCARD}/usr/lib/armbian" "${SDCARD}/etc/systemd/system"

	cat <<- 'AUTODETECT_SH' > "${SDCARD}/usr/lib/armbian/armbian-nvidia-autodetect"
		#!/bin/sh
		# armbian-nvidia-autodetect: installed by build/extensions/nvidia.sh.
		# start: NVIDIA GPU (PCI vendor 10de) present: enable the driver.
		#        Else blacklist the driver and mark its packages for removal.
		# stop:  at shutdown, remove the marked packages.

		BLACKLIST=/etc/modprobe.d/armbian-nvidia-disabled.conf
		# Kept until the removal completes, so a failed removal runs again.
		MARK=/var/lib/armbian/nvidia-remove

		log() {
			echo "armbian-nvidia-autodetect: $*" | systemd-cat -t armbian-nvidia-autodetect 2> /dev/null || true
		}

		# Driver packages with files on the system, also partly removed ones:
		# NVIDIA repository, Ubuntu numbered and Debian names.
		installed() {
			dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' \
				'nvidia-dkms-*' 'nvidia-driver-*' nvidia-driver nvidia-kernel-dkms \
				nvidia-open-kernel-dkms nvidia-open nvidia-kernel-open-dkms \
				nvidia-settings nvidia-common 2> /dev/null |
				awk 'substr($1, 2, 1) != "n" {print $2}' | tr '\n' ' '
		}

		case "${1:-start}" in
			start)
				command -v lspci > /dev/null 2>&1 || exit 0
				if lspci -nn 2> /dev/null | grep -qi '\[10de:'; then
					# The image ships the blacklist. Remove it and load the driver now.
					# The initramfs keeps the blacklist until its next rebuild.
					if [ -f "$BLACKLIST" ]; then
						rm -f "$BLACKLIST"
						log "NVIDIA hardware found; driver enabled"
					fi
					rm -f "$MARK"
					modprobe nvidia_drm modeset=1 2> /dev/null || true
					exit 0
				fi
				mkdir -p /etc/modprobe.d
				cat > "$BLACKLIST" <<- EOF
					# Installed by armbian-nvidia-autodetect: no NVIDIA GPU on this host.
					# Delete this file to enable the driver.
					blacklist nvidia
					blacklist nvidia_drm
					blacklist nvidia_modeset
					blacklist nvidia_uvm
				EOF
				grep -qw 'boot=live' /proc/cmdline && exit 0
				if [ -n "$(installed)" ]; then
					mkdir -p "${MARK%/*}"
					: > "$MARK"
				fi
				;;
			stop)
				[ -f "$MARK" ] || exit 0
				pkgs=$(installed)
				log "no NVIDIA hardware; removing ${pkgs:-the remaining dependencies}"
				# A power cut during an earlier removal leaves dpkg interrupted.
				dpkg --configure -a > /dev/null 2>&1 || true
				# The purge can be done already: autoremove then cleans up.
				# shellcheck disable=SC2086 # word splitting is intended
				if { [ -z "$pkgs" ] || DEBIAN_FRONTEND=noninteractive apt-get -y -qq -o DPkg::Lock::Timeout=60 purge $pkgs > /dev/null 2>&1; } &&
					DEBIAN_FRONTEND=noninteractive apt-get -y -qq -o DPkg::Lock::Timeout=60 autoremove --purge > /dev/null 2>&1; then
					rm -f "$MARK"
					log "removed"
				else
					log "removal failed; it runs again at the next shutdown"
				fi
				;;
		esac
		exit 0
	AUTODETECT_SH
	chmod 0755 "${SDCARD}/usr/lib/armbian/armbian-nvidia-autodetect"

	cat <<- 'AUTODETECT_SERVICE' > "${SDCARD}/etc/systemd/system/armbian-nvidia-autodetect.service"
		[Unit]
		Description=Detect NVIDIA hardware; remove the driver if absent
		Documentation=https://github.com/armbian/build/blob/main/extensions/nvidia.sh
		# Start before the display manager. Stop after it, while the
		# local file systems are still mounted.
		After=local-fs.target
		Before=display-manager.service graphical.target

		[Service]
		Type=oneshot
		RemainAfterExit=yes
		ExecStart=/usr/lib/armbian/armbian-nvidia-autodetect start
		ExecStop=/usr/lib/armbian/armbian-nvidia-autodetect stop
		TimeoutStopSec=5min

		[Install]
		WantedBy=multi-user.target
	AUTODETECT_SERVICE

	chroot_sdcard "systemctl enable armbian-nvidia-autodetect.service" ||
		display_alert "Could not enable armbian-nvidia-autodetect.service in chroot" "${EXTENSION}" "warn"
}
