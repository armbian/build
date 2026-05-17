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
		local latest
		latest=$(chroot_sdcard "apt-cache pkgnames 'nvidia-dkms-' 2>/dev/null \
			| grep -E '^nvidia-dkms-[0-9]+\$' \
			| sed 's/nvidia-dkms-//' \
			| sort -nr | head -1")
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

	# Install the runtime hardware-detection helper. On hosts that
	# happen to have NVIDIA hardware this is a no-op; on hosts that
	# don't, it blacklists the modules and purges the packages so
	# DKMS doesn't rebuild them on every kernel update.
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
		NVIDIA_PKGS=$(dpkg-query -W -f='${binary:Package}\n' \
			'nvidia-dkms-*' 'nvidia-driver-*' \
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
