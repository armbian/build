# SPDX-License-Identifier: GPL-2.0-only
# Keep source firmware while using the common RISC-V GRUB layout.
function post_family_config__950_mangopi_grub_firmware() {
    declare -g MANGOPI_GRUB_BOOTSOURCE="${BOOTSOURCE}"
    declare -g MANGOPI_GRUB_BOOTCONFIG="${BOOTCONFIG}"
}
function extension_prepare_config__900_mangopi_grub() {
    declare -g BOOTSOURCE="${MANGOPI_GRUB_BOOTSOURCE}"
    declare -g BOOTCONFIG="${MANGOPI_GRUB_BOOTCONFIG}"
	declare -g SRC_EXTLINUX=no
	declare -g UEFI_GRUB_TIMEOUT=3
	declare -g UEFI_GRUB_DISABLE_OS_PROBER=true
	declare -g UEFI_GRUB_TERMINAL="console"
	local -a kernel_args grub_args=()
	local arg
	read -r -a kernel_args <<< "${SRC_CMDLINE}"
	for arg in "${kernel_args[@]}"; do
		case "$arg" in ro | rw) continue ;; esac
		grub_args+=("$arg")
	done
	declare -g GRUB_CMDLINE_LINUX_DEFAULT="${grub_args[*]} no_console_suspend consoleblank=0 net.ifnames=0"
}
# Preserve each kernel's DTB for kernel selection and package updates.
function post_family_tweaks_bsp__mangopi_grub_dtb() {
	mkdir -p "${destination}/etc/grub.d" "${destination}/etc/kernel/postinst.d"
	cp "${SRC}/packages/blobs/grub/09_mangopi_linux" "${destination}/etc/grub.d/09_mangopi_linux"
	cp "${SRC}/packages/blobs/grub/armbian-grub-with-dtb" "${destination}/etc/kernel/postinst.d/armbian-grub-with-dtb"
	chmod 755 "${destination}/etc/grub.d/09_mangopi_linux" "${destination}/etc/kernel/postinst.d/armbian-grub-with-dtb"
	printf 'BOOT_FDT_FILE="%s"\n' "${BOOT_FDT_FILE}" > "${destination}/etc/armbian-grub-with-dtb"
}
# Prepare the DTB wrapper before the common GRUB installer runs.
function pre_umount_final_image__100_mangopi_grub_dtb() {
	deploy_qemu_binary_to_chroot "${MOUNT}" "mangopi-grub"
	mount_chroot "${MOUNT}"
	chroot_custom "${MOUNT}" 'dpkg-statoverride --list /etc/grub.d/10_linux >/dev/null || dpkg-statoverride --add --update root root 0644 /etc/grub.d/10_linux'
	chroot_custom "${MOUNT}" 'uuid=$(grub-probe --target=fs_uuid /); path="/dev/disk/by-uuid/$uuid"; test -e "$path" || mkdir -p "$path"'
	chroot_custom "${MOUNT}" 'for k in $(linux-version list); do /etc/kernel/postinst.d/armbian-grub-with-dtb "$k"; done'
	umount_chroot "${MOUNT}/"
	# Remove direct boot files so the ESP EFI loader is the boot path.
	rm -f "${MOUNT}/boot/boot.scr" "${MOUNT}/boot/boot.cmd" "${MOUNT}/boot/extlinux/extlinux.conf"
}
