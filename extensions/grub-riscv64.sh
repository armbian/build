# This runs *after* user_config. Don't change anything not coming from other variables or meant to be configured by the user.
function extension_prepare_config__prepare_grub-riscv64() {
	display_alert "Prepare config" "${EXTENSION}" "info"
	# Extension configuration defaults.
	export DISTRO_GENERIC_KERNEL=${DISTRO_GENERIC_KERNEL:-no}                    # if yes, does not build our own kernel, instead, uses generic one from distro
	export UEFI_GRUB_TERMINAL="${UEFI_GRUB_TERMINAL:-serial console}"            # 'serial' forces grub menu on serial console. empty to not include
	export UEFI_GRUB_DISABLE_OS_PROBER="${UEFI_GRUB_DISABLE_OS_PROBER:-}"        # 'true' will disable os-probing, useful for SD cards.
	export UEFI_GRUB_DISTRO_NAME="${UEFI_GRUB_DISTRO_NAME:-RV64OS}"             # Will be used on grub menu display
	export UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-0}                             # Small timeout by default
	export UEFI_ENABLE_BIOS_AMD64="${UEFI_ENABLE_BIOS_AMD64:-no}"               # Enable BIOS too if target is amd64
	export UEFI_EXPORT_KERNEL_INITRD="${UEFI_EXPORT_KERNEL_INITRD:-no}"          # Export kernel and initrd for direct kernel boot "kexec"
	# User config overrides.
	export BOOTCONFIG="none"                                                     # To try and convince lib/ to not build or install u-boot.
	unset BOOTSOURCE                                                             # To try and convince lib/ to not build or install u-boot.
	export IMAGE_PARTITION_TABLE="gpt"                                           # GPT partition table is essential for many UEFI-like implementations, eg Apple+Intel stuff.
	export UEFISIZE=256                                                          # in MiB - grub EFI is tiny - but some EFI BIOSes ignore small too small EFI partitions
	export BOOTSIZE=0                                                            # No separate /boot when using UEFI.
	export CLOUD_INIT_CONFIG_LOCATION="${CLOUD_INIT_CONFIG_LOCATION:-/boot/efi}" # use /boot/efi for cloud-init as default when using Grub.
	export EXTRA_BSP_NAME="${EXTRA_BSP_NAME}-grub"                               # Unique bsp name.
	export UEFI_GRUB_TARGET_BIOS=""                                              # Target for BIOS GRUB install, set to i386-pc when UEFI_ENABLE_BIOS_AMD64=yes and target is amd64

	if [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then
	display_alert "Prepare config Ubuntu" "${EXTENSION}" "info"

	local uefi_packages="efibootmgr efivar cloud-initramfs-growroot os-prober grub-efi-${ARCH}-bin grub-efi-${ARCH}"

	elif [[ "${DISTRIBUTION}" == "Debian" ]]; then
	display_alert "Prepare Debian" "${EXTENSION}" "info"

	local uefi_packages=""

		# Debian's prebuilt kernels dont support hvc0, hack.
		if [[ "${SERIALCON}" == "hvc0" ]]; then
			display_alert "Debian's kernels don't support hvc0, changing to ttyS0" "${DISTRIBUTION}" "wrn"
			export SERIALCON="ttyS0"
		fi
	fi

	DISTRO_KERNEL_PACKAGES=""
	DISTRO_FIRMWARE_PACKAGES=""

	export PACKAGE_LIST_BOARD="${PACKAGE_LIST_BOARD} ${DISTRO_FIRMWARE_PACKAGES} ${DISTRO_KERNEL_PACKAGES} ${uefi_packages}"

	display_alert "Activating" "GRUB with SERIALCON=${SERIALCON}; timeout ${UEFI_GRUB_TIMEOUT}; BIOS=${UEFI_GRUB_TARGET_BIOS}" ""
}

pre_umount_final_image__install_grub() {

	if [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then

	configure_grub
	local chroot_target=$MOUNT
	display_alert "Installing bootloader" "GRUB" "info"

	# getting rid of the dtb package, if installed, is hard. for now just zap it, otherwise update-grub goes bananas
	mkdir -p "$MOUNT"/boot/efi/dtb
	cp -r "$MOUNT"/boot/dtb/* "$MOUNT"/boot/efi/dtb/

	# add config to disable os-prober, otherwise image will have the host's other OSes boot entries.
	cat <<-grubCfgFragHostSide >>"${MOUNT}"/etc/default/grub.d/99-rv64os-host-side.cfg
		GRUB_DISABLE_OS_PROBER=true
	grubCfgFragHostSide

	# Mount the chroot...
	mount_chroot "$chroot_target/" # this already handles /boot/efi which is required for it to work.

	sed -i 's,devicetree,echo,g' "$MOUNT"/etc/grub.d/10_linux >>"${DEST}"/"${LOG_SUBPATH}"/grub-n.log 2>&1
	cp -r $SRC/packages/blobs/jetson/boot.png "$MOUNT"/boot/grub

	local install_grub_cmdline="update-grub && grub-install --verbose --target=${UEFI_GRUB_TARGET} --no-nvram --removable"
	display_alert "Installing GRUB EFI..." "${UEFI_GRUB_TARGET}" ""
	chroot "$chroot_target" /bin/bash -c "$install_grub_cmdline" >>"$DEST"/"${LOG_SUBPATH}"/install.log 2>&1 || {
		exit_with_error "${install_grub_cmdline} failed!"
	}

	# Remove host-side config.
	rm -f "${MOUNT}"/etc/default/grub.d/99-rv64os-host-side.cfg

	local root_uuid
	root_uuid=$(blkid -s UUID -o value "${LOOP}p2") # get the uuid of the root partition, this has been transposed

	umount_chroot "$chroot_target/"

fi

}

pre_umount_final_image__900_export_kernel_and_initramfs() {
	if [[ "${UEFI_EXPORT_KERNEL_INITRD}" == "yes" ]]; then
		display_alert "Exporting Kernel and Initrd for" "kexec" "info"
		# this writes to ${DESTIMG} directly, since debootstrap.sh will move them later.
		# capture the $MOUNT/boot/vmlinuz and initrd and send it out ${DESTIMG}
		cp "$MOUNT"/boot/vmlinuz-* "${DESTIMG}/${version}.kernel"
		cp "$MOUNT"/boot/initrd.img-* "${DESTIMG}/${version}.initrd"
	fi
}

configure_grub() {
	display_alert "GRUB EFI kernel cmdline" "console=${SERIALCON} distro=${UEFI_GRUB_DISTRO_NAME} timeout=${UEFI_GRUB_TIMEOUT}" ""

	if [[ "_${SERIALCON}_" != "__" ]]; then
		cat <<-grubCfgFrag >>"${MOUNT}"/etc/default/grub.d/98-rv64os.cfg
			GRUB_CMDLINE_LINUX_DEFAULT="console=${SERIALCON}"        # extra Kernel cmdline is configured here
		grubCfgFrag
	fi

	cat <<-grubCfgFrag >>"${MOUNT}"/etc/default/grub.d/98-rv64os.cfg
		GRUB_TIMEOUT_STYLE=menu                                  # Show the menu with Kernel options (RV64OS or -generic)...
		GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT}                        # ... for ${UEFI_GRUB_TIMEOUT} seconds, then boot the RV64OS default.
		GRUB_DISTRIBUTOR="${UEFI_GRUB_DISTRO_NAME}"              # On GRUB menu will show up as "RV64OS GNU/Linux" (will show up in some UEFI BIOS boot menu (F8?) as "rv64os", not on others)
	grubCfgFrag

	if [[ "a${UEFI_GRUB_DISABLE_OS_PROBER}" != "a" ]]; then
		cat <<-grubCfgFragHostSide >>"${MOUNT}"/etc/default/grub.d/98-rv64os.cfg
			GRUB_DISABLE_OS_PROBER=${UEFI_GRUB_DISABLE_OS_PROBER}
		grubCfgFragHostSide
	fi

	if [[ "a${UEFI_GRUB_TERMINAL}" != "a" ]]; then
		cat <<-grubCfgFragTerminal >>"${MOUNT}"/etc/default/grub.d/98-rv64os.cfg
			GRUB_TERMINAL="${UEFI_GRUB_TERMINAL}"
		grubCfgFragTerminal
	fi
}
