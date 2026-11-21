# Package Negroni UFS images for the vendor ABL.

function add_host_dependencies__negroni_ufs() {
	EXTRA_BUILD_DEPS+=("build-tools::mkbootimg")
}

function post_family_tweaks_bsp__negroni_kernel_hook() {
	local input="${SRC}/packages/bsp/oneplus-negroni"
	install -Dm755 "$input/pack-ufs-boot" "${destination}/usr/lib/negroni/pack-ufs-boot"
	install -Dm755 "$input/zz-update-negroni-boot" "${destination}/etc/initramfs/post-update.d/zz-update-negroni-boot"
}

function pre_update_initramfs__negroni_ufs() {
	local root_device uuid
	root_device=$(findmnt -n -o SOURCE --mountpoint "${MOUNT}")
	[[ "${ROOTFS_TYPE}" == ext4 && "$root_device" == "${LOOP}p1" && -b "$root_device" ]] ||
		exit_with_error "Negroni UFS output requires a single ext4 root partition" "$root_device"
	uuid=$(blkid -p -s UUID -o value "$root_device")
	[[ "$uuid" =~ ^[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}$ ]] ||
		exit_with_error "Missing Negroni root filesystem UUID" "$root_device"
	declare -g NEGRONI_UFS_UUID="$uuid"

	mkdir -p "${MOUNT}/etc/initramfs-tools/conf.d" "${MOUNT}/etc/systemd/system"
	# ABL concatenates this archive directly after the legacy LZ4 vendor ramdisk.
	printf 'COMPRESS=lz4\n' > "${MOUNT}/etc/initramfs-tools/conf.d/negroni-compress"
	printf 'ROOT=UUID=%s\n' "$uuid" > "${MOUNT}/etc/initramfs-tools/conf.d/negroni-root"
	install -Dm755 "${SRC}/packages/bsp/oneplus-negroni/init-ufs" "${MOUNT}/usr/lib/negroni/init-ufs"
	cat > "${MOUNT}/etc/initramfs-tools/hooks/negroni-init" <<- 'EOF'
		#!/bin/sh
		set -eu
		[ "${1:-}" != prereqs ] || exit 0
		mkdir -p "$DESTDIR/negroni"
		cp /usr/bin/busybox "$DESTDIR/negroni/busybox"
		mv "$DESTDIR/init" "$DESTDIR/negroni/initramfs-init"
		cp /usr/lib/negroni/init-ufs "$DESTDIR/init"
	EOF
	chmod 755 "${MOUNT}/etc/initramfs-tools/hooks/negroni-init"
	# Grow ext4 inside userdata. Keep the vendor partition table.
	local resize_dropin="${MOUNT}/etc/systemd/system/armbian-resize-filesystem.service.d"
	mkdir -p "$resize_dropin"
	cat > "$resize_dropin/10-negroni-ufs.conf" <<- 'EOF'
		[Service]
		ExecCondition=/bin/sh -ec 'test "$(findmnt -nro FSTYPE /)" = ext4; test "$(lsblk -dnro PARTLABEL "$(findmnt -nro SOURCE /)")" = userdata'
		ExecStart=
		ExecStart=/bin/sh -ec 'resize2fs "$(findmnt -nro SOURCE /)"'
		ExecStartPost=/usr/bin/systemctl disable armbian-resize-filesystem.service
	EOF
	install -Dm755 "${SRC}/packages/bsp/oneplus-negroni/usb-gadget" "${MOUNT}/usr/lib/negroni/usb-gadget"
	cat > "${MOUNT}/etc/systemd/system/negroni-usb-gadget.service" <<- 'EOF'
		[Unit]
		Description=Negroni USB maintenance console
		Before=serial-getty@ttyGS0.service

		[Service]
		Type=oneshot
		RemainAfterExit=yes
		ExecStart=/usr/lib/negroni/usb-gadget

		[Install]
		WantedBy=multi-user.target
	EOF
	systemctl --root="${MOUNT}" enable negroni-usb-gadget.service serial-getty@ttyGS0.service
}

function pre_umount_final_image__negroni_ufs() {
	local -a kernels=("${MOUNT}"/boot/vmlinuz-*)
	local kernel="${kernels[0]:-}"
	local kernel_name="${kernel##*/}"

	[[ ${#kernels[@]} -eq 1 && -s "${kernel}" ]] ||
		exit_with_error "Expected one installed Negroni kernel" "${MOUNT}/boot"
	local initrd="${MOUNT}/boot/initrd.img-${kernel_name#vmlinuz-}"
	local ufs_boot="${DESTIMG}/${version}.ufs-boot.img"
	"${SRC}/packages/bsp/oneplus-negroni/pack-ufs-boot" "$kernel" "$initrd" --output "$ufs_boot" ||
		exit_with_error "Cannot pack Negroni boot image" "$ufs_boot"
}

function post_umount_final_image__negroni_ufs() {
	local partition="${LOOP}p1"
	[[ -b "$partition" && "$(blkid -p -s UUID -o value "$partition")" == "${NEGRONI_UFS_UUID}" ]] ||
		exit_with_error "Negroni root partition changed during image build" "$partition"
	dd if="$partition" of="${DESTIMG}/${version}.rootfs.img" bs=4M conv=sparse status=none
	(
		cd "${DESTIMG}" || exit 1
		sha256sum "${version}.ufs-boot.img" "${version}.rootfs.img" > "${version}.negroni.sha256"
	)
}

function post_build_image__negroni_remove_disk_image() {
	rm -- "${FINAL_IMAGE_FILE}"
}
