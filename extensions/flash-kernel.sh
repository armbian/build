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
	export VER="${FK__PUBLISHED_KERNEL_VERSION}"                                # For the VERSION
	export EXTRA_BSP_NAME="${EXTRA_BSP_NAME}-fk${FK__PUBLISHED_KERNEL_VERSION}" # Unique bsp name.
	echo "-- starting" >"${DEST}"/debug/flash-kernel.log                        # Zero out the log for this extension.
}

function post_install_kernel_debs__install_kernel_and_flash_packages() {
	if [[ "${FK__EXTRA_PACKAGES}" != "" ]]; then
		display_alert "Installing flash-kernel extra packages" "${FK__EXTRA_PACKAGES}"
		echo "-- install extra pkgs" >>"${DEST}"/debug/flash-kernel.log
		chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get ${APT_EXTRA_DIST_PARAMS} -yqq --no-install-recommends install ${FK__EXTRA_PACKAGES}" >>"${DEST}"/debug/flash-kernel.log || {
			display_alert "Failed to install flash-kernel's extra packages." "${EXTENSION}" "err"
			exit 28
		}
	fi

	if [[ "${FK__KERNEL_PACKAGES}" != "" ]]; then
		display_alert "Installing flash-kernel kernel packages" "${FK__KERNEL_PACKAGES}"
		echo "-- install kernel pkgs" >>"${DEST}"/debug/flash-kernel.log
		chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get ${APT_EXTRA_DIST_PARAMS} -yqq --no-install-recommends install ${FK__KERNEL_PACKAGES}" >>"${DEST}"/debug/flash-kernel.log || {
			display_alert "Failed to install flash-kernel's kernel packages." "${EXTENSION}" "err"
			exit 28
		}
	else
		# Using armbian-built kernel, but with Ubuntu's firmware.
		unset KERNELSOURCE # weird, but when done at this point in time, means "don't install armbian-firmware"
	fi

	display_alert "Installing flash-kernel package" "${FK__TOOL_PACKAGE}"
	# Create a fake /sys/firmware/efi directory so that flash-kernel does not try to do anything when installed
	# @TODO: this might or not work after flash-kernel 3.104 or later
	umount "${SDCARD}"/sys
	mkdir -p "${SDCARD}"/sys/firmware/efi

	echo "-- install flash-kernel package" >>"${DEST}"/debug/flash-kernel.log
	chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get ${APT_EXTRA_DIST_PARAMS} -yqq --no-install-recommends install ${FK__TOOL_PACKAGE}" >>"${DEST}"/debug/flash-kernel.log || {
		display_alert "Failed to install flash-kernel package." "${EXTENSION}" "err"
		exit 28
	}

	# Remove fake /sys/firmware (/efi) directory
	rm -rf "${SDCARD}"/sys/firmware
}

# @TODO: extract u-boot into an extension, so that core bsps don't have this stuff in there to begin with.
pre_umount_final_image__remove_uboot_initramfs_hook() {
	# disarm bomb that was planted by the core bsp.
	rm -f "$MOUNT"/etc/initramfs/post-update.d/99-uboot
}

function pre_update_initramfs__setup_flash_kernel() {
	local chroot_target=$MOUNT
	cp /usr/bin/"$QEMU_BINARY" "$chroot_target"/usr/bin/
	mount_chroot "$chroot_target/" # this already handles /boot/firmware which is required for it to work.
	# hack, umount the chroot's /sys, otherwise flash-kernel tries to EFI flash due to the build host (!) being EFI
	umount "$chroot_target/sys"

	echo "--  flash-kernel disabling hooks" >>"${DEST}"/debug/flash-kernel.log
	chroot "$chroot_target" /bin/bash -c "chmod -v -x /etc/kernel/postinst.d/initramfs-tools" >>"${DEST}"/debug/flash-kernel.log 2>&1
	chroot "$chroot_target" /bin/bash -c "chmod -v -x /etc/initramfs/post-update.d/flash-kernel" >>"${DEST}"/debug/flash-kernel.log 2>&1

	export FIRMWARE_DIR="${MOUNT}"/boot/firmware
	call_extension_method "pre_initramfs_flash_kernel" <<-'PRE_INITRAMFS_FLASH_KERNEL'
		*prepare to update-initramfs before flashing kernel via flash_kernel*
		A good spot to write firmware config to ${FIRMWARE_DIR} (/boot/firmware) before flash-kernel actually runs.
	PRE_INITRAMFS_FLASH_KERNEL

	local update_initramfs_cmd="update-initramfs -c -k all"
	display_alert "Updating flash-kernel initramfs..." "$update_initramfs_cmd" ""
	echo "--  flash-kernel initramfs" >>"${DEST}"/debug/flash-kernel.log
	chroot "$chroot_target" /bin/bash -c "$update_initramfs_cmd" >>"${DEST}"/debug/flash-kernel.log 2>&1 || {
		display_alert "Failed to run '$update_initramfs_cmd'" "Check ${DEST}/debug/flash-kernel.log" "err"
		exit 29
	}

	call_extension_method "pre_flash_kernel" <<-'PRE_FLASH_KERNEL'
		*run before running flash-kernel*
		Each board might need different stuff for flash-kernel to work. Implement it here.
		Write to `${MOUNT}`, eg: `"${MOUNT}"/etc/flash-kernel`
	PRE_FLASH_KERNEL

	local flash_kernel_cmd="flash-kernel --machine '${FK__MACHINE_MODEL}'"
	display_alert "flash-kernel" "${FK__MACHINE_MODEL}" "info"
	echo "--  flash-kernel itself" >>"${DEST}"/debug/flash-kernel.log
	chroot "$chroot_target" /bin/bash -c "${flash_kernel_cmd}" >>"${DEST}"/debug/flash-kernel.log 2>&1 || {
		display_alert "Failed to run '${flash_kernel_cmd}'" "Check ${DEST}/debug/flash-kernel.log" "err"
		exit 29
	}

	display_alert "Re-enabling" "initramfs-tools/flash-kernel hook for kernel"
	echo "--  flash-kernel re-enabling hooks" >>"${DEST}"/debug/flash-kernel.log
	chroot "$chroot_target" /bin/bash -c "chmod -v +x /etc/kernel/postinst.d/initramfs-tools" >>"${DEST}"/debug/flash-kernel.log 2>&1
	chroot "$chroot_target" /bin/bash -c "chmod -v +x /etc/initramfs/post-update.d/flash-kernel" >>"${DEST}"/debug/flash-kernel.log 2>&1

	umount_chroot "$chroot_target/"
	rm "$chroot_target"/usr/bin/"$QEMU_BINARY"
}
