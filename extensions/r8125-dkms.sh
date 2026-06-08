# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2026 ifroncy01
#
# Realtek RTL8125B DKMS driver for EasePi-A2 (rk35xx vendor kernel)
#
# The in-kernel r8169 driver on vendor kernel 6.1.115 has a TX path bug
# with RTL8125B (XID 641), causing DHCPv4 and all L2 TX to fail.
# This extension replaces r8169 with the official Realtek r8125 driver
# (v9.016.01) via DKMS, and blacklists r8169.
#
# Only enabled for the vendor branch on easepi-a2 board.

function extension_finish_config__install_r8125_dkms() {
	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping r8125 dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with r8125 dkms" "${EXTENSION}" "debug"

	# Pre-download r8125 DKMS source on the host side (which has direct GitHub access).
	# The Docker container may not have direct GitHub access (e.g. when using ghproxy).
	local r8125_cache_dir="${SRC}/cache/r8125-dkms"
	local r8125_tarball_url="https://github.com/awesometic/realtek-r8125-dkms/archive/refs/heads/master.tar.gz"

	if [[ ! -f "${r8125_cache_dir}/source.tar.gz" ]]; then
		display_alert "Downloading r8125 DKMS source" "${r8125_tarball_url}" "info"
		run_host_command_logged mkdir -p "${r8125_cache_dir}"
		run_host_command_logged curl -fsSL --progress-bar "${r8125_tarball_url}" -o "${r8125_cache_dir}/source.tar.gz"
	fi
}

function post_install_kernel_debs__install_r8125_dkms_package() {
	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0

	display_alert "Installing Realtek r8125 DKMS driver for RTL8125B" "${EXTENSION}" "info"

	# Install DKMS in the chroot
	use_clean_environment="yes" chroot_sdcard_apt_get_install "dkms"

	# Copy pre-downloaded r8125 source into the chroot
	local r8125_cache_dir="${SRC}/cache/r8125-dkms"
	cp "${r8125_cache_dir}/source.tar.gz" "${SDCARD}/tmp/r8125.tar.gz"

	# Extract r8125 source into /usr/src/r8125-9.016.01
	use_clean_environment="yes" chroot_sdcard "mkdir -p /usr/src/r8125-9.016.01"
	use_clean_environment="yes" chroot_sdcard "tar -xzf /tmp/r8125.tar.gz -C /tmp/"
	use_clean_environment="yes" chroot_sdcard "cp -a /tmp/realtek-r8125-dkms-master/. /usr/src/r8125-9.016.01/"
	use_clean_environment="yes" chroot_sdcard "rm -rf /tmp/r8125.tar.gz /tmp/realtek-r8125-dkms-master"

	# Build and install the kernel module via DKMS
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/r8125*/*/build/*.log")
	display_alert "Building r8125 kernel module via DKMS" "${EXTENSION}" "info"

	# Build the full target kernel version string
	# IMAGE_INSTALLED_KERNEL_VERSION provides the base version (e.g., "6.1.115")
	# We need to append BRANCH and LINUXFAMILY for the full version (e.g., "6.1.115-vendor-rk35xx")
	local target_kver="${IMAGE_INSTALLED_KERNEL_VERSION}-${BRANCH}-${LINUXFAMILY}"
	if [[ -z "${target_kver}" ]]; then
		display_alert "Cannot determine target kernel version" "r8125 DKMS build skipped" "warn"
		return 0
	fi
	display_alert "Target kernel version for DKMS" "${target_kver}" "debug"

	use_clean_environment="yes" chroot_sdcard "dkms add -m r8125 -v 9.016.01"
	use_clean_environment="yes" chroot_sdcard "dkms build -m r8125 -v 9.016.01 -k ${target_kver}"
	use_clean_environment="yes" chroot_sdcard "dkms install -m r8125 -v 9.016.01 -k ${target_kver}"

	# Blacklist the in-kernel r8169 driver so r8125 takes over
	use_clean_environment="yes" chroot_sdcard "echo 'blacklist r8169' > /etc/modprobe.d/blacklist-r8169.conf"

	display_alert "r8125 DKMS driver installed, r8169 blacklisted" "${EXTENSION}" "info"
}
