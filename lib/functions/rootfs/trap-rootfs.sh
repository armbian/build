## Prepare/cleanup pair @TODO needs to be split between SDCARD and MOUNT, no sense doing both in rootfs trap anymore
function prepare_rootfs_build_params_and_trap() {
	# add handler to cleanup when done or if something fails or is interrupted.
	add_cleanup_handler trap_handler_cleanup_rootfs_and_image

	# stage: clean and create directories
	run_host_command_logged rm -rfv "${SDCARD}" "${MOUNT}"
	run_host_command_logged mkdir -pv "${SDCARD}" "${MOUNT}" "${SRC}/cache/rootfs" "${DEST}/images" # @TODO images needs its own trap

	# bind mount rootfs if defined # @TODO: is this used? Igor's NAS?
	if [[ -d "${ARMBIAN_CACHE_ROOTFS_PATH}" ]]; then
		display_alert "Warning, using untested code path" "ARMBIAN_CACHE_ROOTFS_PATH" "warn"
		mountpoint -q "${SRC}"/cache/rootfs && umount "${SRC}"/cache/rootfs
		mount --bind "${ARMBIAN_CACHE_ROOTFS_PATH}" "${SRC}/cache/rootfs"
	fi

	# stage: verify tmpfs configuration and mount
	# CLI needs ~2GiB, desktop ~5GiB
	# vs 60% of "available" RAM (free + buffers + magic)
	declare -i available_physical_memory_mib
	available_physical_memory_mib=$(($(awk '/MemAvailable/ {print $2}' /proc/meminfo) * 6 / 1024 / 10)) # MiB

	# @TODO: well those are very... arbitrary numbers. At least when using cached rootfs, we can be more precise.
	# predicting the size of tmpfs is hard/impossible, so would be nice to show the used size at the end so we can tune.
	declare -i tmpfs_estimated_size=2000                     # MiB
	[[ $BUILD_DESKTOP == yes ]] && tmpfs_estimated_size=5000 # MiB

	declare use_tmpfs=no                      # by default
	if [[ ${FORCE_USE_RAMDISK} == no ]]; then # do not use, even if it fits
		display_alert "Not using tmpfs for rootfs" "due to FORCE_USE_RAMDISK=no" "info"
	elif [[ ${FORCE_USE_RAMDISK} == yes || ${available_physical_memory_mib} -gt ${tmpfs_estimated_size} ]]; then # use, either force or fits
		use_tmpfs=yes
		display_alert "Using tmpfs for rootfs build" "RAM available: ${available_physical_memory_mib}MiB > ${tmpfs_estimated_size}MiB estimated" "info"
	else
		display_alert "Not using tmpfs for rootfs" "RAM available: ${available_physical_memory_mib}MiB < ${tmpfs_estimated_size}MiB estimated" "info"
	fi

	# make global and readonly, for sanity
	declare -g -r -i tmpfs_estimated_size="${tmpfs_estimated_size}"
	declare -g -r -i available_physical_memory_mib="${available_physical_memory_mib}"

	if [[ $use_tmpfs == yes ]]; then
		declare -g -r ROOTFS_IS_UNDER_TMPFS=yes
		mount -t tmpfs tmpfs "${SDCARD}" # do not specify size; we've calculated above that it should fit, and Linux will try its best if it doesn't.
	fi
}

function trap_handler_cleanup_rootfs_and_image() {
	display_alert "Cleanup for rootfs and image" "trap_handler_cleanup_rootfs_and_image" "cleanup"

	debug_tmpfs_show_usage "before cleanup of rootfs"

	cd "${SRC}" || echo "Failed to cwd to ${SRC}" # Move pwd away, so unmounts work
	# those will loop until they're unmounted.
	umount_chroot_recursive "${SDCARD}" "SDCARD" || true
	umount_chroot_recursive "${MOUNT}" "MOUNT" || true

	# unmount tmpfs mounted on SDCARD if it exists. #@TODO: move to new tmpfs-utils scheme
	mountpoint -q "${SDCARD}" && umount "${SDCARD}"

	# @TODO: rpardini: igor: why lazy umounts?
	mountpoint -q "${SRC}"/cache/toolchain && umount -l "${SRC}"/cache/toolchain >&2
	mountpoint -q "${SRC}"/cache/rootfs && umount -l "${SRC}"/cache/rootfs >&2
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose "${ROOT_MAPPER}" >&2

	if [[ "${PRESERVE_SDCARD_MOUNT}" == "yes" ]]; then
		display_alert "Preserving SD card mount" "trap_handler_cleanup_rootfs_and_image" "warn"
		return 0
	fi

	# shellcheck disable=SC2153 # global var.
	if [[ -b "${LOOP}" ]]; then
		display_alert "Freeing loop" "trap_handler_cleanup_rootfs_and_image ${LOOP}" "wrn"
		free_loop_device_insistent "${LOOP}" || true
	fi

	[[ -d "${SDCARD}" ]] && rm -rf --one-file-system "${SDCARD}"
	[[ -d "${MOUNT}" ]] && rm -rf --one-file-system "${MOUNT}"
	[[ -f "${SDCARD}".raw ]] && rm -f "${SDCARD}".raw

	return 0 # short-circuit above, so exit clean here
}
