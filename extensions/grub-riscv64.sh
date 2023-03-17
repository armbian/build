#!/usr/bin/env bash
# This runs *after* user_config. Don't change anything not coming from other variables or meant to be configured by the user.
function extension_prepare_config__prepare_grub-riscv64() {
	display_alert "Prepare config" "${EXTENSION}" "info"
	# Extension configuration defaults.
	export DISTRO_GENERIC_KERNEL=${DISTRO_GENERIC_KERNEL:-no}             # if yes, does not build our own kernel, instead, uses generic one from distro
	export UEFI_GRUB_TERMINAL="${UEFI_GRUB_TERMINAL:-serial console}"     # 'serial' forces grub menu on serial console. empty to not include
	export UEFI_GRUB_DISABLE_OS_PROBER="${UEFI_GRUB_DISABLE_OS_PROBER:-}" # 'true' will disable os-probing, useful for SD cards.
	export UEFI_GRUB_DISTRO_NAME="${UEFI_GRUB_DISTRO_NAME:-Armbian}"      # Will be used on grub menu display
	export UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-0}                      # Small timeout by default
	export GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT:-""}" # Cmdline by default
	# User config overrides.
	export BOOTCONFIG="none"                                                     # To try and convince lib/ to not build or install u-boot.
	unset BOOTSOURCE                                                             # To try and convince lib/ to not build or install u-boot.
	export IMAGE_PARTITION_TABLE="gpt"                                           # GPT partition table is essential for many UEFI-like implementations, eg Apple+Intel stuff.
	export UEFISIZE=256                                                          # in MiB - grub EFI is tiny - but some EFI BIOSes ignore small too small EFI partitions
	export BOOTSIZE=0                                                            # No separate /boot when using UEFI.
	export CLOUD_INIT_CONFIG_LOCATION="${CLOUD_INIT_CONFIG_LOCATION:-/boot/efi}" # use /boot/efi for cloud-init as default when using Grub.
	export EXTRA_BSP_NAME="${EXTRA_BSP_NAME}-grub"                               # Unique bsp name.
	export UEFI_GRUB_TARGET="riscv64-efi"                                        # Default for x86_64

	if [[ "${DISTRIBUTION}" != "Ubuntu" && "${BUILDING_IMAGE}" == "yes" ]]; then
		exit_with_error "${DISTRIBUTION} is not supported yet"
	fi

	add_packages_to_image efibootmgr efivar cloud-initramfs-growroot os-prober "grub-efi-${ARCH}-bin" "grub-efi-${ARCH}"

	display_alert "Activating" "GRUB with SERIALCON=${SERIALCON}; timeout ${UEFI_GRUB_TIMEOUT}; target=${UEFI_GRUB_TARGET}" ""
}

pre_umount_final_image__install_grub() {

	configure_grub
	local chroot_target="${MOUNT}"
	display_alert "Installing bootloader" "GRUB" "info"

	# RiscV64 specific: actually copy the DTBs to the ESP
	display_alert "Copying DTBs to ESP" "${EXTENSION}" "info"
	run_host_command_logged mkdir -pv "${chroot_target}"/boot/efi/dtb
	run_host_command_logged cp -rpv "${chroot_target}"/boot/dtb/* "${chroot_target}"/boot/efi/dtb/
	# RiscV64 specific: @TODO ??? what is this ??
	sed -i 's,devicetree,echo,g' "${chroot_target}"/etc/grub.d/10_linux

	# add config to disable os-prober, otherwise image will have the host's other OSes boot entries.
	cat <<- grubCfgFragHostSide >> "${chroot_target}"/etc/default/grub.d/99-armbian-host-side.cfg
		GRUB_DISABLE_OS_PROBER=true
	grubCfgFragHostSide

	# copy Armbian GRUB wallpaper
	run_host_command_logged mkdir -pv "${chroot_target}"/usr/share/images/grub/
	run_host_command_logged cp -pv "${SRC}"/packages/blobs/splash/grub.png "${chroot_target}"/usr/share/images/grub/wallpaper.png

	# Mount the chroot...
	mount_chroot "${chroot_target}/" # this already handles /boot/efi which is required for it to work.

	# update-grub is secretly `grub-mkconfig` under wraps, but the actual work is done by /etc/grub.d/10-linux
	# that decides based on 'test -e "/dev/disk/by-uuid/${GRUB_DEVICE_UUID}"' so that _must_ exist.
	# If it does NOT exist, then a reference to a /dev/devYpX is used, and will fail to boot.
	# Irony: let's use grub-probe to find out the UUID of the root partition, and then create a symlink to it.
	# Another: on some systems (eg, not Docker) the thing might already exist due to udev actually working.
	# shellcheck disable=SC2016 # some wierd escaping going on there.
	chroot_custom "$chroot_target" mkdir -pv '/dev/disk/by-uuid/"$(grub-probe --target=fs_uuid /)"' "||" true

	display_alert "Creating GRUB config..." "${EXTENSION}: grub-mkconfig / update-grub"
	chroot_custom "$chroot_target" update-grub || {
		exit_with_error "update-grub failed!"
	}

	local install_grub_cmdline="grub-install --target=${UEFI_GRUB_TARGET} --no-nvram --removable" # nvram is global to the host, even across chroot. take care.
	display_alert "Installing GRUB EFI..." "${EXTENSION}: ${UEFI_GRUB_TARGET}"
	chroot_custom "$chroot_target" "$install_grub_cmdline" || {
		exit_with_error "${install_grub_cmdline} failed!"
	}

	### Sanity check. The produced "/boot/grub/grub.cfg" should:
	declare -i has_failed_sanity_check=0

	# - NOT have any mention of `/dev` inside; otherwise something is going to fail
	if grep -q '/dev' "${chroot_target}/boot/grub/grub.cfg"; then
		display_alert "GRUB sanity check failed" "grub.cfg contains /dev" "err"
		SHOW_LOG=yes run_host_command_logged grep '/dev' "${chroot_target}/boot/grub/grub.cfg" "||" true
		has_failed_sanity_check=1
	else
		display_alert "GRUB config sanity check passed" "no '/dev' found in grub.cfg" "info"
	fi

	# - HAVE references to initrd, otherwise going to fail.
	if ! grep -q 'initrd.img' "${chroot_target}/boot/grub/grub.cfg"; then
		display_alert "GRUB config sanity check failed" "no initrd.img references found in /boot/grub/grub.cfg" "err"
		has_failed_sanity_check=1
	else
		display_alert "GRUB config sanity check passed" "initrd.img references found OK in /boot/grub/grub.cfg" "debug"
	fi

	if [[ ${has_failed_sanity_check} -gt 0 ]]; then
		exit_with_error "GRUB config sanity check failed, image will be unbootable; see above errors"
	fi

	# Remove host-side config.
	rm -f "${MOUNT}"/etc/default/grub.d/99-armbian-host-side.cfg

	umount_chroot "$chroot_target/"

}

configure_grub() {
	[[ -n "$SERIALCON" ]] &&
		GRUB_CMDLINE_LINUX_DEFAULT+=" console=${SERIALCON}"

	[[ "$BOOT_LOGO" == "yes" || "$BOOT_LOGO" == "desktop" && "$BUILD_DESKTOP" == "yes" ]] &&
		GRUB_CMDLINE_LINUX_DEFAULT+=" quiet splash plymouth.ignore-serial-consoles i915.force_probe=* loglevel=3" ||
		GRUB_CMDLINE_LINUX_DEFAULT+=" splash=verbose i915.force_probe=*"

	# Enable Armbian Wallpaper on GRUB
	if [[ "${VENDOR}" == Armbian ]]; then
		mkdir -p "${MOUNT}"/usr/share/desktop-base/
		cat <<- grubWallpaper >> "${MOUNT}"/usr/share/desktop-base/grub_background.sh
			WALLPAPER=/usr/share/images/grub/wallpaper.png
			COLOR_NORMAL=white/black
			COLOR_HIGHLIGHT=black/white
		grubWallpaper
		run_host_command_logged chmod -v +x "${MOUNT}"/usr/share/desktop-base/grub_background.sh
	fi

	display_alert "GRUB EFI kernel cmdline" "'${GRUB_CMDLINE_LINUX_DEFAULT}' distro=${UEFI_GRUB_DISTRO_NAME} timeout=${UEFI_GRUB_TIMEOUT}" ""
	cat <<- grubCfgFrag >> "${MOUNT}"/etc/default/grub.d/98-armbian.cfg
		GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT}"
		GRUB_TIMEOUT_STYLE=menu                                  # Show the menu with Kernel options (Armbian or -generic)...
		GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT}                        # ... for ${UEFI_GRUB_TIMEOUT} seconds, then boot the Armbian default.
		GRUB_DISTRIBUTOR="${UEFI_GRUB_DISTRO_NAME}"              # On GRUB menu will show up as "Armbian GNU/Linux" (will show up in some UEFI BIOS boot menu (F8?) as "armbian", not on others)
		GRUB_GFXMODE=1024x768
		GRUB_GFXPAYLOAD=keep
	grubCfgFrag

	if [[ "a${UEFI_GRUB_DISABLE_OS_PROBER}" != "a" ]]; then
		cat <<- grubCfgFragHostSide >> "${MOUNT}"/etc/default/grub.d/98-armbian.cfg
			GRUB_DISABLE_OS_PROBER=${UEFI_GRUB_DISABLE_OS_PROBER}
		grubCfgFragHostSide
	fi

	if [[ "a${UEFI_GRUB_TERMINAL}" != "a" ]]; then
		cat <<- grubCfgFragTerminal >> "${MOUNT}"/etc/default/grub.d/98-armbian.cfg
			GRUB_TERMINAL="${UEFI_GRUB_TERMINAL}"
		grubCfgFragTerminal
	fi
}
