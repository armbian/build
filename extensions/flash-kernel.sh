#!/usr/bin/env bash
# This runs *after* user_config. Don't change anything not coming from other variables or meant to be configured by the user.
function extension_prepare_config__prepare_flash_kernel() {
	# Configuration defaults, or lack thereof.
	export FK__TOOL_PACKAGE="${FK__TOOL_PACKAGE:-flash-kernel}"
	export FK__PUBLISHED_KERNEL_VERSION="${FK__PUBLISHED_KERNEL_VERSION:-undefined-flash-kernel-version}"
	export FK__EXTRA_PACKAGES="${FK__EXTRA_PACKAGES:-undefined-flash-kernel-kernel-package}"
	export FK__KERNEL_PACKAGES="${FK__KERNEL_PACKAGES:-}"
	export FK__MACHINE_MODEL="${FK__MACHINE_MODEL:-Undefined Flash-Kernel Machine}"

	# Override certain variables. A case of "this extension knows better and modifies user configurable stuff".
	export BOOTCONFIG="none"                                                    # To try and convince lib/ to not build or install u-boot.
	unset BOOTSOURCE                                                            # To try and convince lib/ to not build or install u-boot.
	export UEFISIZE=256                                                         # in MiB. Not really UEFI, but partition layout is the same.
	export BOOTSIZE=0                                                           # No separate /boot, flash-kernel will "flash" the kernel+initrd to the firmware part.
	export UEFI_MOUNT_POINT="/boot/firmware"                                    # mount uefi partition at /boot/firmware
	export CLOUD_INIT_CONFIG_LOCATION="/boot/firmware"                          # use /boot/firmware for cloud-init as well
	export IMAGE_INSTALLED_KERNEL_VERSION="${FK__PUBLISHED_KERNEL_VERSION}"     # For the VERSION
	export EXTRA_BSP_NAME="${EXTRA_BSP_NAME}-fk${FK__PUBLISHED_KERNEL_VERSION}" # Unique bsp name.
}

function post_install_kernel_debs__install_kernel_and_flash_packages() {
	export INSTALL_ARMBIAN_FIRMWARE="no" # Disable Armbian-firmware install, which would happen after this method.

	if [[ "${FK__EXTRA_PACKAGES}" != "" ]]; then
		display_alert "Installing flash-kernel extra packages" "${FK__EXTRA_PACKAGES}"
		chroot_sdcard_apt_get_install "${FK__EXTRA_PACKAGES}" || {
			display_alert "Failed to install flash-kernel's extra packages." "${EXTENSION}" "err"
			exit 28
		}
	fi

	if [[ "${FK__KERNEL_PACKAGES}" != "" ]]; then
		display_alert "Installing flash-kernel kernel packages" "${FK__KERNEL_PACKAGES}"
		chroot_sdcard_apt_get_install "${FK__KERNEL_PACKAGES}" || {
			display_alert "Failed to install flash-kernel's kernel packages." "${EXTENSION}" "err"
			exit 28
		}
	fi

	display_alert "Installing flash-kernel package" "${FK__TOOL_PACKAGE}"
	# Create a fake /sys/firmware/efi directory so that flash-kernel does not try to do anything when installed
	# @TODO: this might or not work after flash-kernel 3.104 or later
	umount "${SDCARD}"/sys
	mkdir -p "${SDCARD}"/sys/firmware/efi

	chroot_sdcard_apt_get_install "${FK__TOOL_PACKAGE}" || {
		display_alert "Failed to install flash-kernel package." "${EXTENSION}" "err"
		exit 28
	}

	# Remove fake /sys/firmware (/efi) directory
	rm -rf "${SDCARD}"/sys/firmware

	return 0 # prevent future shortcircuits exiting with error
}

# @TODO: extract u-boot into an extension, so that core bsps don't have this stuff in there to begin with.
# @TODO: this code is duplicated in grub.sh extension, so another reason to refactor the root of the evil
post_family_tweaks_bsp__remove_uboot_flash_kernel() {
	display_alert "Removing uboot from BSP" "${EXTENSION}" "info"
	# Simply remove everything with 'uboot' or 'u-boot' in their filenames from the BSP package.
	# shellcheck disable=SC2154 # $destination is the target dir of the bsp building function
	find "$destination" -type f | grep -e "uboot" -e "u-boot" | xargs rm
}

pre_umount_final_image__remove_uboot_initramfs_hook_flash_kernel() {
	# even if BSP still contained this (cached .deb), make sure by removing from ${MOUNT}
	[[ -f "$MOUNT"/etc/initramfs/post-update.d/99-uboot ]] && rm -v "$MOUNT"/etc/initramfs/post-update.d/99-uboot
	return 0 # shortcircuit above
}

function pre_update_initramfs__setup_flash_kernel() {
	local chroot_target=$MOUNT
	deploy_qemu_binary_to_chroot "${chroot_target}"
	mount_chroot "$chroot_target/" # this already handles /boot/firmware which is required for it to work.
	# hack, umount the chroot's /sys, otherwise flash-kernel tries to EFI flash due to the build host (!) being EFI
	umount "$chroot_target/sys"

	chroot_custom "$chroot_target" chmod -v -x "/etc/kernel/postinst.d/initramfs-tools"
	chroot_custom "$chroot_target" chmod -v -x "/etc/initramfs/post-update.d/flash-kernel"

	export FIRMWARE_DIR="${MOUNT}"/boot/firmware
	call_extension_method "pre_initramfs_flash_kernel" <<- 'PRE_INITRAMFS_FLASH_KERNEL'
		*prepare to update-initramfs before flashing kernel via flash_kernel*
		A good spot to write firmware config to ${FIRMWARE_DIR} (/boot/firmware) before flash-kernel actually runs.
	PRE_INITRAMFS_FLASH_KERNEL

	local update_initramfs_cmd="update-initramfs -c -k all"
	display_alert "Updating flash-kernel initramfs..." "$update_initramfs_cmd" ""
	chroot_custom "$chroot_target" "$update_initramfs_cmd" || {
		display_alert "Failed to run '$update_initramfs_cmd'" "Check logs" "err"
		exit 29
	}

	call_extension_method "pre_flash_kernel" <<- 'PRE_FLASH_KERNEL'
		*run before running flash-kernel*
		Each board might need different stuff for flash-kernel to work. Implement it here.
		Write to `${MOUNT}`, eg: `"${MOUNT}"/etc/flash-kernel`
	PRE_FLASH_KERNEL

	local flash_kernel_cmd="FK_FORCE=yes flash-kernel --machine '${FK__MACHINE_MODEL}'" # FK_FORCE=yes is required since flash-kernel 3.104ubuntu14 / 3.106ubuntu7
	display_alert "flash-kernel" "${FK__MACHINE_MODEL}" "info"
	chroot_custom "$chroot_target" "${flash_kernel_cmd}" || {
		display_alert "Failed to run '${flash_kernel_cmd}'" "Check logs" "err"
		exit 29
	}

	display_alert "Re-enabling" "initramfs-tools/flash-kernel hook for kernel"
	chroot_custom "$chroot_target" chmod -v +x "/etc/kernel/postinst.d/initramfs-tools"
	chroot_custom "$chroot_target" chmod -v +x "/etc/initramfs/post-update.d/flash-kernel"

	umount_chroot "${chroot_target}/"
	undeploy_qemu_binary_from_chroot "${chroot_target}"

	display_alert "Disabling Armbian-core update_initramfs, was already done above." "${EXTENSION}"
	unset KERNELSOURCE # ugly. sorry. we'll have better mechanism for this soon. this is tested at lib/debootstrap.sh:844
}
