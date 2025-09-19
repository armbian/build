#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2025 Mecid Urganci <mecid@meco.media>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/

function extension_prepare_config__prepare_systemd_boot_standard() {
	declare -g DISTRO_GENERIC_KERNEL=${DISTRO_GENERIC_KERNEL:-no}
	declare -g SYSTEMD_BOOT_TIMEOUT=${SYSTEMD_BOOT_TIMEOUT:-3}
	declare -g SYSTEMD_BOOT_DEFAULT_ENTRY=${SYSTEMD_BOOT_DEFAULT_ENTRY:-""}
	declare -g SYSTEMD_BOOT_EDITOR=${SYSTEMD_BOOT_EDITOR:-no}
	declare -g SYSTEMD_BOOT_CONSOLE=${SYSTEMD_BOOT_CONSOLE:-""}
	declare -g SYSTEMD_BOOT_DISTRO_NAME=${SYSTEMD_BOOT_DISTRO_NAME:-Armbian}
	declare -g SYSTEMD_BOOT_CMDLINE=${SYSTEMD_BOOT_CMDLINE:-""}
	declare -g UEFI_ENABLE_BIOS_AMD64="${UEFI_ENABLE_BIOS_AMD64:-no}"

	declare -a packages=()

	declare -g BOOTCONFIG="none"
	unset BOOTSOURCE
	declare -g IMAGE_PARTITION_TABLE="gpt"
	declare -g UEFISIZE=1024 # Some weird mkfs.vfat bug for <512mb with FAT32 for sector size 4096that the UEFI fat driver cannot handle. Use 1024mb to be safe.
	declare -g BOOTSIZE=0
	declare -g CLOUD_INIT_CONFIG_LOCATION="${CLOUD_INIT_CONFIG_LOCATION:-/boot/efi}"
	declare -g EXTRA_BSP_NAME="${EXTRA_BSP_NAME}-systemd-boot"

	packages+=(systemd-boot efibootmgr efivar cloud-initramfs-growroot busybox)

	if [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then
		DISTRO_KERNEL_VER="generic"
		DISTRO_KERNEL_PACKAGES="linux-image-generic"
		DISTRO_FIRMWARE_PACKAGES="linux-firmware"
	elif [[ "${DISTRIBUTION}" == "Debian" ]]; then
		DISTRO_KERNEL_VER="${ARCH}"
		DISTRO_KERNEL_PACKAGES="linux-image-${ARCH}"
		DISTRO_FIRMWARE_PACKAGES="firmware-linux-free"
		if [[ "${SERIALCON}" == "hvc0" ]]; then
			display_alert "Debian's kernels don't support hvc0, changing to ttyS0" "${DISTRIBUTION}" "wrn"
			declare -g SERIALCON="ttyS0"
		fi
	fi

	if [[ "${DISTRO_GENERIC_KERNEL}" == "yes" ]]; then
		declare -g IMAGE_INSTALLED_KERNEL_VERSION="${DISTRO_KERNEL_VER}"
		declare -g KERNELSOURCE='none'
		declare -g INSTALL_ARMBIAN_FIRMWARE=no
	else
		declare -g KERNELDIR="linux-uefi-${LINUXFAMILY}"
		DISTRO_KERNEL_PACKAGES=""
		DISTRO_FIRMWARE_PACKAGES=""
	fi

	# shellcheck disable=SC2086
	add_packages_to_image ${DISTRO_FIRMWARE_PACKAGES} ${DISTRO_KERNEL_PACKAGES} "${packages[@]}"

	display_alert "Extension: ${EXTENSION}: activating" "systemd-boot with SERIALCON=${SERIALCON}; timeout ${SYSTEMD_BOOT_TIMEOUT}" ""
}

function post_family_tweaks_bsp__remove_uboot_systemd_boot() {
	display_alert "Removing uboot from BSP" "${EXTENSION}" "info"
	# shellcheck disable=SC2154
	pushd "${destination}" || exit_with_error "cray-cray about destination: ${destination}"
	run_host_command_logged find "." -type f "|" grep -e "uboot" -e "u-boot" "|" xargs rm -v
	popd
}

function pre_umount_final_image__remove_uboot_initramfs_hook_systemd_boot() {
	[[ -f "$MOUNT"/etc/initramfs/post-update.d/99-uboot ]] && rm -v "$MOUNT"/etc/initramfs/post-update.d/99-uboot
	return 0
}

function pre_umount_final_image__install_systemd_boot() {
	local chroot_target="${MOUNT}"

	# Get PARTUUID early, after filesystem exists but before any chroot operations
	local root_uuid=$(blkid -s PARTUUID -o value "${LOOP}p2")
	display_alert "Extension: ${EXTENSION}: Detected root PARTUUID" "${root_uuid}" "info"

	if [[ -z "${root_uuid}" ]]; then
		exit_with_error "Extension: ${EXTENSION}: Could not detect root filesystem PARTUUID"
	fi

	configure_systemd_boot_with_uuid "${root_uuid}"
	display_alert "Extension: ${EXTENSION}: Installing bootloader" "systemd-boot" "info"

	display_alert "Extension: ${EXTENSION}: Ensuring systemd-boot config directory exists" "" "info"
	mkdir -p "${MOUNT}/etc/systemd-boot.d"

	mkdir -p "${MOUNT}"/boot/efi/dtb

	if [[ -n "${BOOT_FDT_FILE}" ]]; then
		install_dtb_for_systemd_boot
	fi

	create_systemd_boot_kernel_hook

	call_extension_method "systemd_boot_early_config" <<- 'SYSTEMD_BOOT_EARLY_CONFIG'
		Allow for early systemd-boot configuration.
		This is called after `configure_systemd_boot`.
		chroot ($MOUNT) is *not* mounted yet.
	SYSTEMD_BOOT_EARLY_CONFIG

	mount_chroot "$chroot_target/"

	call_extension_method "systemd_boot_pre_install" <<- 'SYSTEMD_BOOT_PRE_INSTALL'
		Last-minute hook for systemd-boot tweaks before actually installing systemd-boot.
		The chroot ($MOUNT) is mounted.
	SYSTEMD_BOOT_PRE_INSTALL

	display_alert "Extension: ${EXTENSION}: Installing systemd-boot..." "" ""

	chroot_custom "$chroot_target" bootctl install --no-variables || {
		exit_with_error "bootctl install failed!"
	}

	mkdir -p "${chroot_target}/boot/efi/loader"

	cat <<- EOD > "${chroot_target}/boot/efi/loader/loader.conf"
		timeout ${SYSTEMD_BOOT_TIMEOUT}
		console-mode keep
		editor ${SYSTEMD_BOOT_EDITOR}
	EOD

	if [[ -n "${SYSTEMD_BOOT_DEFAULT_ENTRY}" ]]; then
		echo "default ${SYSTEMD_BOOT_DEFAULT_ENTRY}" >> "${chroot_target}/boot/efi/loader/loader.conf"
	fi

	mkdir -p "${chroot_target}/boot/efi/loader/entries"

	if [[ "${DISTRO_GENERIC_KERNEL}" == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}: Using Distro Generic Kernel" "update_initramfs with IMAGE_INSTALLED_KERNEL_VERSION: ${DISTRO_KERNEL_VER}" "debug"
		IMAGE_INSTALLED_KERNEL_VERSION="${DISTRO_KERNEL_VER}" update_initramfs "${MOUNT}"
	else
		display_alert "Extension: ${EXTENSION}: Running update-initramfs for all kernels" "" "debug"
		chroot_custom "$chroot_target" update-initramfs -c -k all || {
			exit_with_error "update-initramfs failed!"
		}
	fi

	# Create initial boot entries with correct UUID before unmounting
	display_alert "Extension: ${EXTENSION}: Creating initial boot entries" "" "info"
	for kernel_file in $(ls "${MOUNT}/boot/vmlinuz-"* 2>/dev/null); do
		local kernel_version=$(basename "${kernel_file}" | sed 's/vmlinuz-//')
		create_boot_entry_with_uuid "${kernel_version}" "${root_uuid}"
	done

	call_extension_method "systemd_boot_late_config" <<- 'SYSTEMD_BOOT_LATE_CONFIG'
		Allow for late systemd-boot configuration.
		This is called after bootctl install and entry generation.
		chroot ($MOUNT) is mounted. sanity checks are going to be performed.
	SYSTEMD_BOOT_LATE_CONFIG

	declare -i has_failed_sanity_check=0

	if ! [[ -d "${chroot_target}/boot/efi/EFI/systemd" ]]; then
		display_alert "systemd-boot sanity check failed" "systemd-boot EFI directory not found" "err"
		has_failed_sanity_check=1
	else
		display_alert "Extension: ${EXTENSION}: systemd-boot config sanity check passed" "EFI directory found" "debug"
	fi

	if ! ls "${chroot_target}/boot/efi/loader/entries"/*.conf >/dev/null 2>&1; then
		display_alert "systemd-boot sanity check failed" "No boot entries found in /boot/efi/loader/entries" "err"
		has_failed_sanity_check=1
	else
		display_alert "Extension: ${EXTENSION}: systemd-boot config sanity check passed" "Boot entries found" "debug"
	fi

	if [[ ${has_failed_sanity_check} -gt 0 ]]; then
		exit_with_error "Extension: ${EXTENSION}: systemd-boot config sanity check failed, image will be unbootable; see above errors"
	fi

	umount_chroot "$chroot_target/"
}

function pre_umount_final_image__900_export_kernel_and_initramfs() {
	if [[ "${UEFI_EXPORT_KERNEL_INITRD}" == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}: Exporting Kernel and Initrd for" "kexec" "info"
		run_host_command_logged ls -la "${MOUNT}"/boot/vmlinuz-* "${MOUNT}"/boot/initrd.img-* || true
		run_host_command_logged cp -pv "${MOUNT}"/boot/vmlinuz-* "${DESTIMG}/${version}.kernel"
		run_host_command_logged cp -pv "${MOUNT}"/boot/initrd.img-* "${DESTIMG}/${version}.initrd"
	fi
}

function install_dtb_for_systemd_boot() {
	display_alert "Extension: ${EXTENSION}: Installing DTB file" "${BOOT_FDT_FILE}" "info"

	cat <<- EOD > "${MOUNT}/etc/armbian-systemd-boot-dtb"
		BOOT_FDT_FILE="${BOOT_FDT_FILE}"
	EOD

	mkdir -p "${MOUNT}/boot/efi/dtb"

	local default_kernel_version=$(ls "${MOUNT}"/boot/vmlinuz-* 2>/dev/null | head -n1 | sed -e 's|.*/vmlinuz-||')

	if [[ -n "$default_kernel_version" ]]; then
		display_alert "Extension: ${EXTENSION}: Copying DTB for kernel" "${default_kernel_version}" "info"
		local dtb_source="/usr/lib/linux-image-${default_kernel_version}/${BOOT_FDT_FILE}"
		local dtb_target="/boot/efi/dtb/${BOOT_FDT_FILE##*/}"

		if [[ -f "${MOUNT}${dtb_source}" ]]; then
			run_host_command_logged cp -v "${MOUNT}${dtb_source}" "${MOUNT}${dtb_target}"
		else
			display_alert "Extension: ${EXTENSION}: DTB file not found" "${dtb_source}" "warn"
		fi
	else
		display_alert "Extension: ${EXTENSION}: No kernel found, DTB installation deferred to kernel hook" "" "info"
	fi
}

function create_boot_entry_with_uuid() {
	local kernel_version="$1"
	local root_uuid="$2"
	local entry_file="${MOUNT}/boot/efi/loader/entries/armbian-${kernel_version}.conf"

	display_alert "Extension: ${EXTENSION}: Creating boot entry for kernel" "${kernel_version}" "info"

	# Copy kernel files to ESP
	cp -f "${MOUNT}/boot/vmlinuz-${kernel_version}" "${MOUNT}/boot/efi/vmlinuz-${kernel_version}"
	cp -f "${MOUNT}/boot/initrd.img-${kernel_version}" "${MOUNT}/boot/efi/initrd.img-${kernel_version}"

	# Construct kernel command line
	local cmdline="root=PARTUUID=${root_uuid} rw"

	# Add console configuration if specified
	if [[ -n "${SYSTEMD_BOOT_CONSOLE}" ]]; then
		cmdline+=" ${SYSTEMD_BOOT_CONSOLE}"
	fi

	# Add serial console if specified
	if [[ -n "${SERIALCON}" && "${SERIALCON}" != "tty1" && "${SERIALCON}" != "tty0" ]]; then
		cmdline+=" console=${SERIALCON}"
	fi

	# Add additional kernel command line parameters
	if [[ -n "${SYSTEMD_BOOT_CMDLINE}" ]]; then
		cmdline+=" ${SYSTEMD_BOOT_CMDLINE}"
	fi

	# Boot logo/splash settings
	if [[ "$BOOT_LOGO" == "yes" || "$BOOT_LOGO" == "desktop" && "$BUILD_DESKTOP" == "yes" ]]; then
		cmdline+=" quiet splash plymouth.ignore-serial-consoles i915.force_probe=* loglevel=3"
	else
		cmdline+=" splash=verbose i915.force_probe=*"
	fi

	# Create entry with correct UUID from the start
	cat <<- EOD > "${entry_file}"
		title ${SYSTEMD_BOOT_DISTRO_NAME} (${kernel_version})
		version ${kernel_version}
		linux /vmlinuz-${kernel_version}
		initrd /initrd.img-${kernel_version}
		options ${cmdline}
	EOD

	# Add DTB if needed
	if [[ -n "${BOOT_FDT_FILE}" ]]; then
		echo "devicetree /dtb/${BOOT_FDT_FILE##*/}" >> "${entry_file}"
	fi

	display_alert "Extension: ${EXTENSION}: Boot entry created" "${entry_file}" "debug"
}

function create_systemd_boot_kernel_hook() {
	display_alert "Extension: ${EXTENSION}: Adding systemd-boot kernel hook" "" "info"

	mkdir -p "${MOUNT}"/etc/kernel/postinst.d
	mkdir -p "${MOUNT}"/etc/kernel/prerm.d

	# Replace the conflicting Ubuntu systemd boot entry script with our own stub
	if [[ -f "${MOUNT}/usr/lib/kernel/install.d/90-loaderentry.install" ]]; then
		display_alert "Extension: ${EXTENSION}: Replacing systemd loaderentry script with Armbian stub" "" "info"

		# Backup original
		cp "${MOUNT}/usr/lib/kernel/install.d/90-loaderentry.install" "${MOUNT}/usr/lib/kernel/install.d/90-loaderentry.install.orig"

		# Create our stub that only handles removal
		cat > "${MOUNT}/usr/lib/kernel/install.d/90-loaderentry.install" <<- 'EOF'
			#!/bin/bash
			# Armbian systemd-boot extension stub
			# Only handle removal, installation is handled by Armbian hook

			COMMAND="$1"
			KERNEL_VERSION="$2"

			case "$COMMAND" in
				remove)
					# Clean up our Armbian entries when kernel is removed
					if [[ -f "/boot/efi/loader/entries/armbian-${KERNEL_VERSION}.conf" ]]; then
						echo "Armbian: Removing boot entry for ${KERNEL_VERSION}" >&2
						rm -f "/boot/efi/loader/entries/armbian-${KERNEL_VERSION}.conf"
						rm -f "/boot/efi/vmlinuz-${KERNEL_VERSION}"
						rm -f "/boot/efi/initrd.img-${KERNEL_VERSION}"
					fi
					;;
				add)
					# Do nothing - let Armbian handle this
					echo "Armbian: Kernel installation handled by Armbian hook" >&2
					;;
			esac
			exit 0
		EOF
		chmod +x "${MOUNT}/usr/lib/kernel/install.d/90-loaderentry.install"
	fi

	# Create kernel removal hook
	cat <<- 'EOF' > "${MOUNT}"/etc/kernel/prerm.d/armbian-systemd-boot
		#!/bin/bash
		set -e

		kversion="$1"
		echo "Armbian: Removing systemd-boot entry for kernel $kversion" >&2

		# Remove our boot entry and files
		if [[ -f "/boot/efi/loader/entries/armbian-${kversion}.conf" ]]; then
			rm -f "/boot/efi/loader/entries/armbian-${kversion}.conf"
			echo "Armbian: Removed boot entry for ${kversion}" >&2
		fi

		if [[ -f "/boot/efi/vmlinuz-${kversion}" ]]; then
			rm -f "/boot/efi/vmlinuz-${kversion}"
			echo "Armbian: Removed kernel file for ${kversion}" >&2
		fi

		if [[ -f "/boot/efi/initrd.img-${kversion}" ]]; then
			rm -f "/boot/efi/initrd.img-${kversion}"
			echo "Armbian: Removed initrd file for ${kversion}" >&2
		fi

		# Update bootctl
		if command -v bootctl >/dev/null; then
			bootctl update || echo "Armbian: Warning - bootctl update failed" >&2
		fi
	EOF
	chmod +x "${MOUNT}"/etc/kernel/prerm.d/armbian-systemd-boot

	# Create the main installation hook
	cat <<- 'EOD' > "${MOUNT}"/etc/kernel/postinst.d/armbian-systemd-boot
		#!/bin/bash
		set -e
		set -x

		kversion="$1"
		echo "Armbian: Running systemd-boot kernel hook for $kversion" >&2

		# Handle DTB if configured
		if [[ -f /etc/armbian-systemd-boot-dtb ]]; then
			source /etc/armbian-systemd-boot-dtb
			if [[ -n "$BOOT_FDT_FILE" ]]; then
				echo "Armbian: Installing DTB for systemd-boot: $BOOT_FDT_FILE" >&2

				mkdir -p /boot/efi/dtb

				source_dtb_file="/usr/lib/linux-image-${kversion}/${BOOT_FDT_FILE}"
				target_dtb_file="/boot/efi/dtb/${BOOT_FDT_FILE##*/}"

				if [[ -f "$source_dtb_file" ]]; then
					echo "Armbian: Copying DTB: $source_dtb_file -> $target_dtb_file" >&2
					cp -v "$source_dtb_file" "$target_dtb_file"
				else
					echo "Armbian: Warning - DTB file not found: $source_dtb_file" >&2
				fi
			fi
		else
			echo "Armbian: No DTB configuration found" >&2
		fi

		echo "Armbian: Creating systemd-boot entry for kernel $kversion" >&2

		mkdir -p /boot/efi/loader/entries

		# Get root PARTUUID from stored configuration
		root_uuid=""
		if [[ -f /etc/systemd-boot.d/armbian-config ]]; then
			source /etc/systemd-boot.d/armbian-config
			if [[ -n "${ROOT_UUID}" ]]; then
				root_uuid="${ROOT_UUID}"
				echo "Armbian: Using stored root PARTUUID: ${root_uuid}" >&2
			fi
		fi

		# Fallback to runtime detection if no stored PARTUUID
		if [[ -z "${root_uuid}" ]]; then
			echo "Armbian: No stored PARTUUID found, detecting at runtime" >&2
			root_partition=$(mount | grep ' on / ' | cut -d' ' -f1 | sed 's/\/dev\///')
			root_uuid=$(blkid -s PARTUUID -o value "/dev/${root_partition}")
			echo "Armbian: Runtime detected root PARTUUID: ${root_uuid}" >&2
		fi

		if [[ -z "${root_uuid}" ]]; then
			echo "Armbian: ERROR - Could not determine root PARTUUID" >&2
			exit 1
		fi

		entry_file="/boot/efi/loader/entries/armbian-${kversion}.conf"

		# Copy kernel files to ESP
		echo "Armbian: Copying kernel and initrd to ESP" >&2
		cp -f /boot/vmlinuz-${kversion} /boot/efi/vmlinuz-${kversion}
		cp -f /boot/initrd.img-${kversion} /boot/efi/initrd.img-${kversion}

		# Load systemd-boot configuration
		if [[ -f /etc/systemd-boot.d/armbian-config ]]; then
			source /etc/systemd-boot.d/armbian-config
		fi

		# Construct kernel command line
		cmdline="root=PARTUUID=${root_uuid} rw"

		# Add console configuration if specified
		if [[ -n "${SYSTEMD_BOOT_CONSOLE}" ]]; then
			cmdline+=" ${SYSTEMD_BOOT_CONSOLE}"
		fi

		# Add serial console configuration if specified and not tty1 or tty0
		# This is the new block to add!
		if [[ -n "${SERIALCON}" && "${SERIALCON}" != "tty1" && "${SERIALCON}" != "tty0" ]]; then
			cmdline+=" console=${SERIALCON}"
		fi

		# Add additional kernel command line parameters
		if [[ -n "${SYSTEMD_BOOT_CMDLINE}" ]]; then
			cmdline+=" ${SYSTEMD_BOOT_CMDLINE}"
		fi

		# Create boot entry
		cat > "$entry_file" <<- ENTRY_EOF
			title ${SYSTEMD_BOOT_DISTRO_NAME:-Armbian} (${kversion})
			version ${kversion}
			linux /vmlinuz-${kversion}
			initrd /initrd.img-${kversion}
			options ${cmdline}
		ENTRY_EOF

		# Add DTB if available
		if [[ -f /etc/armbian-systemd-boot-dtb ]]; then
			source /etc/armbian-systemd-boot-dtb
			if [[ -n "$BOOT_FDT_FILE" ]]; then
				echo "devicetree /dtb/${BOOT_FDT_FILE##*/}" >> "$entry_file"
			fi
		fi

		echo "Armbian: Boot entry created at $entry_file" >&2

		# Clean up any existing entries with wrong UUIDs or conflicting paths
		echo "Armbian: Cleaning up conflicting boot entries" >&2
		for existing_entry in /boot/efi/loader/entries/*.conf; do
			if [[ "${existing_entry}" != "${entry_file}" ]] && [[ -f "${existing_entry}" ]]; then
				# Remove entries that point to /ubuntu/ path or have wrong UUID
				if grep -q "linux.*/ubuntu/" "${existing_entry}" || \
				   (grep -q "root=PARTUUID=" "${existing_entry}" && ! grep -q "root=PARTUUID=${root_uuid}" "${existing_entry}"); then
					echo "Armbian: Removing conflicting entry: ${existing_entry}" >&2
					rm -f "${existing_entry}"
				fi
			fi
		done

		# Update bootctl if installed
		if command -v bootctl >/dev/null; then
			echo "Armbian: Running bootctl update" >&2
			bootctl update || echo "Armbian: Warning - bootctl update failed" >&2
		fi

		echo "Armbian: systemd-boot kernel hook completed" >&2
	EOD

	chmod +x "${MOUNT}"/etc/kernel/postinst.d/armbian-systemd-boot
}

function configure_systemd_boot_with_uuid() {
	local root_uuid="$1"
	display_alert "Extension: ${EXTENSION}: Configuring systemd-boot" "SERIALCON=${SERIALCON} PARTUUID=${root_uuid}" "info"

	mkdir -p "${MOUNT}/etc/systemd-boot.d"

	# Store configuration values to be used by kernel hooks
	cat <<- EOD > "${MOUNT}/etc/systemd-boot.d/armbian-config"
		# Armbian systemd-boot configuration
		SYSTEMD_BOOT_DISTRO_NAME="${SYSTEMD_BOOT_DISTRO_NAME}"
		SYSTEMD_BOOT_TIMEOUT="${SYSTEMD_BOOT_TIMEOUT}"
		SYSTEMD_BOOT_EDITOR="${SYSTEMD_BOOT_EDITOR}"
		SYSTEMD_BOOT_CONSOLE="${SYSTEMD_BOOT_CONSOLE}"
		SYSTEMD_BOOT_CMDLINE="${SYSTEMD_BOOT_CMDLINE}"
		ROOT_UUID="${root_uuid}"
		SERIALCON="${SERIALCON}"
	EOD
}
