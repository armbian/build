#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Armbian build script
# https://github.com/armbian/build/

function build_rootfs_and_image() {
	display_alert "Starting rootfs and image building process for" "${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}" "info"

	[[ $ROOTFS_TYPE != ext4 ]] && display_alert "Assuming ${BOARD} ${BRANCH} kernel supports ${ROOTFS_TYPE}" "" "wrn"

	# add handler to cleanup when done or if something fails or is interrupted.
	add_cleanup_handler trap_handler_cleanup_rootfs_and_image

	# stage: clean and create directories
	rm -rf "${SDCARD}" "${MOUNT}"
	mkdir -p "${SDCARD}" "${MOUNT}" "${DEST}/images" "${SRC}/cache/rootfs"

	# bind mount rootfs if defined
	if [[ -d "${ARMBIAN_CACHE_ROOTFS_PATH}" ]]; then
		mountpoint -q "${SRC}"/cache/rootfs && umount "${SRC}"/cache/toolchain
		mount --bind "${ARMBIAN_CACHE_ROOTFS_PATH}" "${SRC}/cache/rootfs"
	fi

	# stage: verify tmpfs configuration and mount
	# CLI needs ~1.5GiB, desktop - ~3.5GiB
	# calculate and set tmpfs mount to use 9/10 of available RAM+SWAP
	# @TODO: this does not make sense; swap should not be considered. Actually, only free + cached memory should be considered!
	local phymem=$(((($(awk '/MemTotal/ {print $2}' /proc/meminfo) + $(awk '/SwapTotal/ {print $2}' /proc/meminfo))) / 1024 * 9 / 10)) # MiB
	local tmpfs_max_size=1500                                                                                                          # MiB
	if [[ $BUILD_DESKTOP == yes ]]; then
		tmpfs_max_size=3500
	fi

	if [[ $FORCE_USE_RAMDISK == no ]]; then
		local use_tmpfs=no
	elif [[ $FORCE_USE_RAMDISK == yes || $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi
	[[ -n $FORCE_TMPFS_SIZE ]] && phymem=$FORCE_TMPFS_SIZE

	if [[ $use_tmpfs == yes ]]; then
		display_alert "Using tmpfs for rootfs" "${phymem}M" "debug"
		mount -t tmpfs -o "size=${phymem}M" tmpfs "${SDCARD}"
	fi

	# stage: prepare basic rootfs: unpack cache or create from scratch
	LOG_SECTION="get_or_create_rootfs_cache_chroot_sdcard" do_with_logging get_or_create_rootfs_cache_chroot_sdcard

	call_extension_method "pre_install_distribution_specific" "config_pre_install_distribution_specific" <<- 'PRE_INSTALL_DISTRIBUTION_SPECIFIC'
		*give config a chance to act before install_distribution_specific*
		Called after `create_rootfs_cache` (_prepare basic rootfs: unpack cache or create from scratch_) but before `install_distribution_specific` (_install distribution and board specific applications_).
	PRE_INSTALL_DISTRIBUTION_SPECIFIC

	# stage: install kernel and u-boot packages
	# install distribution and board specific applications

	LOG_SECTION="install_distribution_specific_${RELEASE}" do_with_logging install_distribution_specific
	LOG_SECTION="install_distribution_agnostic" do_with_logging install_distribution_agnostic

	# install locally built packages #  @TODO: armbian-nextify this eventually
	[[ $EXTERNAL_NEW == compile ]] && LOG_SECTION="packages_local" do_with_logging chroot_installpackages_local

	# install from apt.armbian.com # @TODO: armbian-nextify this eventually
	[[ $EXTERNAL_NEW == prebuilt ]] && LOG_SECTION="packages_prebuilt" do_with_logging chroot_installpackages "yes"

	# stage: user customization script
	# NOTE: installing too many packages may fill tmpfs mount
	LOG_SECTION="customize_image" do_with_logging customize_image

	# remove packages that are no longer needed. rootfs cache + uninstall might have leftovers.
	LOG_SECTION="apt_purge_unneeded_packages" do_with_logging apt_purge_unneeded_packages

	# for reference, debugging / sanity checking
	LOG_SECTION="list_installed_packages" do_with_logging list_installed_packages

	# clean up / prepare for making the image
	umount_chroot "$SDCARD"

	LOG_SECTION="post_debootstrap_tweaks" do_with_logging post_debootstrap_tweaks

	# ------------------------------------ UP HERE IT's 'rootfs' stuff -------------------------------

	#------------------------------------ DOWN HERE IT's 'image' stuff -------------------------------

	if [[ $ROOTFS_TYPE == fel ]]; then
		FEL_ROOTFS=$SDCARD/
		display_alert "Starting FEL boot" "$BOARD" "info"
		start_fel_boot
	else
		LOG_SECTION="prepare_partitions" do_with_logging prepare_partitions
		LOG_SECTION="create_image_from_sdcard_rootfs" do_with_logging create_image_from_sdcard_rootfs
	fi

	# Completely and recursively unmount the directory. This will remove the tmpfs mount too
	umount_chroot_recursive "${SDCARD}"

	# Remove the dir
	[[ -d "${SDCARD}" ]] && rm -rf --one-file-system "${SDCARD}"

	# Run the cleanup handler. @TODO: this already does the above, so can be simpler.
	execute_and_remove_cleanup_handler trap_handler_cleanup_rootfs_and_image

	return 0
}

function list_installed_packages() {
	display_alert "Recording list of installed packages" "asset log" "debug"
	LOG_ASSET="installed_packages.txt" do_with_log_asset chroot_sdcard dpkg --get-selections "| grep -v deinstall | awk '{print \$1}' | cut -f1 -d':'"
}

function trap_handler_cleanup_rootfs_and_image() {
	display_alert "Cleanup for rootfs and image" "trap_handler_cleanup_rootfs_and_image" "cleanup"

	cd "${SRC}" || echo "Failed to cwd to ${SRC}" # Move pwd away, so unmounts work
	# those will loop until they're unmounted.
	umount_chroot_recursive "${SDCARD}" || true
	umount_chroot_recursive "${MOUNT}" || true

	mountpoint -q "${SRC}"/cache/toolchain && umount -l "${SRC}"/cache/toolchain >&2 # @TODO: why does Igor uses lazy umounts? nfs?
	mountpoint -q "${SRC}"/cache/rootfs && umount -l "${SRC}"/cache/rootfs >&2
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose "${ROOT_MAPPER}" >&2

	# shellcheck disable=SC2153 # global var.
	if [[ -b "${LOOP}" ]]; then
		display_alert "Freeing loop" "trap_handler_cleanup_rootfs_and_image ${LOOP}" "wrn"
		losetup -d "${LOOP}" >&2 || true
	fi

	[[ -d "${SDCARD}" ]] && rm -rf --one-file-system "${SDCARD}"
	[[ -d "${MOUNT}" ]] && rm -rf --one-file-system "${MOUNT}"

	return 0 # short-circuit above, so exit clean here
}
