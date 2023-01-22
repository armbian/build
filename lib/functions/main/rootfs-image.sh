#!/usr/bin/env bash

function build_rootfs_and_image() {
	display_alert "Checking for rootfs cache" "$(echo "${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}" | tr -s " ")" "info"
	[[ $ROOTFS_TYPE != ext4 ]] && display_alert "Assuming ${BOARD} ${BRANCH} kernel supports ${ROOTFS_TYPE}" "" "wrn"

	LOG_SECTION="prepare_rootfs_build_params_and_trap" do_with_logging prepare_rootfs_build_params_and_trap

	# get a basic rootfs, either from cache or from scratch
	LOG_SECTION="build_rootfs_only" do_with_logging build_rootfs_only # only occurrence of this

	# stage: with a basic rootfs available, we mount the chroot and work on it
	mount_chroot "${SDCARD}"

	call_extension_method "pre_install_distribution_specific" "config_pre_install_distribution_specific" <<- 'PRE_INSTALL_DISTRIBUTION_SPECIFIC'
		*give config a chance to act before install_distribution_specific*
		Called after `create_rootfs_cache` (_prepare basic rootfs: unpack cache or create from scratch_) but before `install_distribution_specific` (_install distribution and board specific applications_).
	PRE_INSTALL_DISTRIBUTION_SPECIFIC

	# stage: install kernel and u-boot packages
	# install distribution and board specific applications

	LOG_SECTION="install_distribution_specific_${RELEASE}" do_with_logging install_distribution_specific
	LOG_SECTION="install_distribution_agnostic" do_with_logging install_distribution_agnostic

	# install locally built packages  #  @TODO: armbian-nextify this eventually
	#[[ $EXTERNAL_NEW == compile ]] && LOG_SECTION="packages_local" do_with_logging chroot_installpackages_local
	[[ $EXTERNAL_NEW == compile ]] && display_alert "Not running" "NOT armbian-next ported yet: chroot_installpackages_local" "warn"

	# install from apt.armbian.com  # @TODO: armbian-nextify this eventually
	#[[ $EXTERNAL_NEW == prebuilt ]] && LOG_SECTION="packages_prebuilt" do_with_logging chroot_installpackages "yes"
	[[ $EXTERNAL_NEW == prebuilt ]] && display_alert "Not running" "NOT armbian-next ported yet: chroot_installpackages 'yes'" "warn"

	# stage: user customization script
	# NOTE: installing too many packages may fill tmpfs mount
	LOG_SECTION="customize_image" do_with_logging customize_image

	# remove packages that are no longer needed. rootfs cache + uninstall might have leftovers.
	LOG_SECTION="apt_purge_unneeded_packages" do_with_logging apt_purge_unneeded_packages

	# for reference, debugging / sanity checking
	LOG_SECTION="list_installed_packages" do_with_logging list_installed_packages

	LOG_SECTION="post_debootstrap_tweaks" do_with_logging post_debootstrap_tweaks

	# clean up / prepare for making the image
	umount_chroot "$SDCARD"

	# obtain the size, in MiB, of "${SDCARD}" at this point.
	declare -i rootfs_size_mib
	rootfs_size_mib=$(du -sm "${SDCARD}" | awk '{print $1}')
	display_alert "Actual rootfs size" "${rootfs_size_mib}MiB" ""

	# warn if rootfs_size_mib is higher than the tmpfs_estimated_size
	if [[ ${rootfs_size_mib} -gt ${tmpfs_estimated_size} ]]; then
		display_alert "Rootfs post-tweaks size is larger than estimated tmpfs size" "${rootfs_size_mib}MiB > ${tmpfs_estimated_size}MiB" "wrn"
	fi

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

	# Completely and recursively unmount the directory. --> This will remove the tmpfs mount too <--
	umount_chroot_recursive "${SDCARD}" "SDCARD rootfs finished"

	# Remove the dir
	[[ -d "${SDCARD}" ]] && rm -rf --one-file-system "${SDCARD}"

	# Run the cleanup handler. @TODO: this already does the above, so can be simpler. @TODO: don't forget to split MOUNT/SDCARD trap
	execute_and_remove_cleanup_handler trap_handler_cleanup_rootfs_and_image

	return 0
}

function list_installed_packages() {
	display_alert "Recording list of installed packages" "asset log" "debug"
	LOG_ASSET="installed_packages.txt" do_with_log_asset chroot_sdcard dpkg --get-selections "| grep -v deinstall | awk '{print \$1}' | cut -f1 -d':'"
}
