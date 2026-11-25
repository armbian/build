# Qualcomm SM8450 Snapdragon 8 Gen 1 octa core 8/12GB RAM 128/256/512GB UFS phone
# Generate a boot v4 image and an ext4 rootfs image for the stock Qcom ABL
declare -g BOARD_NAME="Negroni"
declare -g BOARD_VENDOR="oneplus"
declare -g BOARDFAMILY="sm8450-negroni"
declare -g INTRODUCED="2022"
declare -g KERNEL_TARGET="edge"
declare -g KERNEL_TEST_TARGET="edge"
declare -g BOOTCONFIG="none"
declare -g BOOT_FDT_FILE="qcom/sm8450-oneplus-negroni.dtb"
declare -g IMAGE_PARTITION_TABLE="gpt"
declare -g HAS_VIDEO_OUTPUT="no"
declare -g EXTRAWIFI="no"
declare -g INSTALL_ARMBIAN_FIRMWARE="no"
declare -g SERIALCON="ttyGS0"

# Needed after installation to rebuild and flash boot_b when the initramfs changes.
declare -g EXTRA_BSPDEPS="busybox-static, lz4, mkbootimg, python3"

# Stock ABL does not accept an appended DTB. The kernel replaces the ABL device tree
# with its built-in Negroni DTB, which also carries the command line (see the
# sm8450-negroni kernel patches), so there is no armbianEnv.txt.

function oneplus-negroni_is_userspace_supported() {
	[[ "${RELEASE}" == "trixie" ]] && return 0
	return 1
}

function add_host_dependencies__oneplus-negroni_mkbootimg() {
	EXTRA_BUILD_DEPS+=("build-tools::mkbootimg")
}

function post_family_tweaks_bsp__oneplus-negroni_boot() {
	local src="${SRC}/packages/bsp/oneplus-negroni"

	install -Dm755 "${src}/pack-ufs-boot" "${destination}/usr/lib/negroni/pack-ufs-boot"
	install -Dm755 "${src}/init-ufs" "${destination}/usr/lib/negroni/init-ufs"
	install -Dm755 "${src}/zz-update-negroni-boot" "${destination}/etc/initramfs/post-update.d/zz-update-negroni-boot"
	install -Dm755 "${src}/initramfs-hook" "${destination}/usr/share/initramfs-tools/hooks/negroni-init"
	# ABL concatenates the initramfs directly after its legacy LZ4 vendor ramdisk.
	install -Dm644 "${src}/initramfs-compress.conf" "${destination}/etc/initramfs-tools/conf.d/negroni-compress"
	# Grow ext4 inside userdata; never touch the vendor partition table.
	install -Dm644 "${src}/resize-filesystem.conf" \
		"${destination}/usr/lib/systemd/system/armbian-resize-filesystem.service.d/10-negroni-ufs.conf"
}

function post_family_tweaks_bsp__oneplus-negroni_usb_gadget() {
	local src="${SRC}/packages/bsp/oneplus-negroni"

	install -Dm755 "${src}/usb-gadget" "${destination}/usr/lib/negroni/usb-gadget"
	install -Dm644 "${src}/negroni-usb-gadget.service" "${destination}/usr/lib/systemd/system/negroni-usb-gadget.service"
}

function post_family_tweaks__oneplus-negroni_userspace() {
	chroot_sdcard systemctl enable negroni-usb-gadget.service

	if ! oneplus-negroni_is_userspace_supported; then
		display_alert "Missing userspace for ${BOARD}" "only trixie is tested; skipping Wi-Fi firmware for ${RELEASE}" "warn"
		return 0
	fi
	# WCN6855 (ath11k) firmware
	do_with_retries 3 chroot_sdcard_apt_get_install firmware-atheros
}

function pre_update_initramfs__oneplus-negroni_root() {
	local root_device uuid
	root_device=$(findmnt -n -o SOURCE --mountpoint "${MOUNT}")
	[[ "${ROOTFS_TYPE}" == ext4 && "$root_device" == "${LOOP}p1" && -b "$root_device" ]] ||
		exit_with_error "Negroni UFS output requires a single ext4 root partition" "$root_device"
	uuid=$(blkid -p -s UUID -o value "$root_device")
	[[ "$uuid" =~ ^[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}$ ]] ||
		exit_with_error "Missing Negroni root filesystem UUID" "$root_device"
	declare -g NEGRONI_UFS_UUID="$uuid"

	# ABL passes no usable command line, so the initramfs finds the root by UUID.
	mkdir -p "${MOUNT}/etc/initramfs-tools/conf.d"
	printf 'ROOT=UUID=%s\n' "$uuid" > "${MOUNT}/etc/initramfs-tools/conf.d/negroni-root"
}

function pre_umount_final_image__oneplus-negroni_boot_image() {
	local -a kernels=("${MOUNT}"/boot/vmlinuz-*)
	local kernel="${kernels[0]:-}"
	local kernel_name="${kernel##*/}"

	[[ ${#kernels[@]} -eq 1 && -s "${kernel}" ]] ||
		exit_with_error "Expected one installed Negroni kernel" "${MOUNT}/boot"
	local initrd="${MOUNT}/boot/initrd.img-${kernel_name#vmlinuz-}"
	local ufs_boot="${DESTIMG}/${version}.ufs-boot.img"
	display_alert "Packing Negroni boot image" "${ufs_boot##*/}" "info"
	"${SRC}/packages/bsp/oneplus-negroni/pack-ufs-boot" "$kernel" "$initrd" --output "$ufs_boot" ||
		exit_with_error "Cannot pack Negroni boot image" "$ufs_boot"
}

function post_umount_final_image__oneplus-negroni_rootfs_image() {
	local partition="${LOOP}p1"
	[[ -b "$partition" && "$(blkid -p -s UUID -o value "$partition")" == "${NEGRONI_UFS_UUID}" ]] ||
		exit_with_error "Negroni root partition changed during image build" "$partition"
	display_alert "Extracting Negroni rootfs image" "${version}.rootfs.img" "info"
	dd if="$partition" of="${DESTIMG}/${version}.rootfs.img" bs=4M conv=sparse status=none
}

# Only the boot and rootfs images are flashed; the GPT disk image has no use on this phone.
function post_build_image__oneplus-negroni_remove_disk_image() {
	rm -- "${FINAL_IMAGE_FILE}"
}
