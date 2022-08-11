export SERIALCON="tty1"                          # Cant reasonably expect UEFI stuff to have a serial console. Customize if otherwise.
export SKIP_BOOTSPLASH="yes"                     # No splash.
export UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-3} # Default 3-seconds timeout for GRUB menu.
export BOARD_FIRMWARE_INSTALL="-full"            # Install full firmware for UEFI boards
case "${BRANCH}" in

	ddk)
		# This will force `unset KERNELSOURCE` later; no kernel will be built.
		# Instead, the distro's default linux-generic kernel will be installed.
		export DISTRO_GENERIC_KERNEL=yes
		;;

	current)
		export DISTRO_GENERIC_KERNEL=no
		export LINUXCONFIG="linux-uefi-${LINUXFAMILY}-${BRANCH}"
		export KERNEL_MAJOR_MINOR="5.15"                      # Major and minor versions of this kernel. For mainline caching.
		export KERNELBRANCH="branch:linux-5.15.y"             # Branch or tag to build from. It should match MAJOR_MINOR
		export KERNELPATCHDIR="uefi-${LINUXFAMILY}-${BRANCH}" # Might be empty.
		;;

	edge)
		export DISTRO_GENERIC_KERNEL=no
		export LINUXCONFIG="linux-uefi-${LINUXFAMILY}-${BRANCH}"
		export KERNEL_MAJOR_MINOR="6.1"                       # Major and minor versions of this kernel. For mainline caching.
		export KERNELBRANCH="branch:linux-6.1.y"              # Branch or tag to build from. It should match MAJOR_MINOR
		export KERNELPATCHDIR="uefi-${LINUXFAMILY}-${BRANCH}" # Might be empty.
		;;
esac

if [[ "${QEMU_UBOOT_BOOTCONFIG}" != "" ]]; then
	# Allowance for using the UEFI kernels, but not an UEFI bootloader, instead, use qemu with uboot.
	# Used in the qemu-uboot-x86 and qemu-uboot-arm64 "boards".
	display_alert "Using UEFI as base for qemu-uboot-${LINUXFAMILY}" "Using BOOTCONFIG: ${QEMU_UBOOT_BOOTCONFIG}" "debug"
	export ATF_COMPILE="no"
	export BOOTSCRIPT="boot-qemu-${LINUXFAMILY}.cmd:boot.cmd"
	export BOOTDIR="qemu-uboot-${LINUXFAMILY}"
	export BOOTSOURCE='https://source.denx.de/u-boot/u-boot.git'
	export BOOTBRANCH='tag:v2022.10'
	export UBOOT_TARGET_MAP="all;;u-boot.rom"                   # Can't find the target that produces 'u-boot.rom', so for now 'make all'
	export PACKAGE_LIST_FAMILY="spice-vdagent qemu-guest-agent" # Nice-to-have packages for running under qemu
	export BOOTCONFIG="${QEMU_UBOOT_BOOTCONFIG}"
	export PACKAGE_LIST_FAMILY_REMOVE="plymouth" # Nice-to-have packages for running under qemu
	export PLYMOUTH="no"                         # try with smaller initrd?

	# A patch to convert to `q35` machine type DTS (x86 only)
	export BOOTPATCHDIR="u-boot-qemu-${LINUXFAMILY}"

	# Config for the qcow2 image
	declare -g QCOW2_RESIZE_AMOUNT="+50G" # resize the qcow2 image to be 50G bigger
	declare -g QCOW2_KEEP_IMG="no"        # produce only the .qcow2 image, not raw .img

	# Enable the qcow2 output extension.
	enable_extension "image-output-qcow2"

	write_uboot_platform() {
		echo "Not writing uboot for qemu-uboot-xxxx platform"
	}

	function pre_umount_final_image__export_uboot_rom() {
		local uboot_name="${CHOSEN_UBOOT}_${REVISION}_${ARCH}"
		display_alert "Exporting u-boot.rom" "${uboot_name} - ${version}.u-boot.rom" "debug"
		run_host_command_logged cp -pv "${MOUNT}/usr/lib/${uboot_name}/u-boot.rom" "${DESTIMG}/${version}.u-boot.rom" || true
	}
fi
