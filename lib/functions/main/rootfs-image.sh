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

	[[ $ROOTFS_TYPE != ext4 ]] && display_alert "Assuming $BOARD $BRANCH kernel supports $ROOTFS_TYPE" "" "wrn"

	# trap to unmount stuff in case of error/manual interruption
	trap unmount_on_exit INT TERM EXIT

	# stage: clean and create directories
	rm -rf $SDCARD $MOUNT
	mkdir -p $SDCARD $MOUNT $DEST/images $SRC/cache/rootfs

	# bind mount rootfs if defined
	if [[ -d "${ARMBIAN_CACHE_ROOTFS_PATH}" ]]; then
		mountpoint -q "${SRC}"/cache/rootfs && umount -l "${SRC}"/cache/toolchain
		mount --bind "${ARMBIAN_CACHE_ROOTFS_PATH}" "${SRC}"/cache/rootfs
	fi

	# stage: verify tmpfs configuration and mount
	# CLI needs ~1.5GiB, desktop - ~3.5GiB
	# calculate and set tmpfs mount to use 9/10 of available RAM+SWAP
	local phymem=$(((($(awk '/MemTotal/ {print $2}' /proc/meminfo) + $(awk '/SwapTotal/ {print $2}' /proc/meminfo))) / 1024 * 9 / 10)) # MiB
	if [[ $BUILD_DESKTOP == yes ]]; then local tmpfs_max_size=3500; else local tmpfs_max_size=1500; fi                                 # MiB
	if [[ $FORCE_USE_RAMDISK == no ]]; then
		local use_tmpfs=no
	elif [[ $FORCE_USE_RAMDISK == yes || $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi
	[[ -n $FORCE_TMPFS_SIZE ]] && phymem=$FORCE_TMPFS_SIZE

	[[ $use_tmpfs == yes ]] && mount -t tmpfs -o size=${phymem}M tmpfs $SDCARD

	# stage: prepare basic rootfs: unpack cache or create from scratch
	LOG_SECTION="get_or_create_rootfs_cache_chroot_sdcard" do_with_logging get_or_create_rootfs_cache_chroot_sdcard

	call_extension_method "pre_install_distribution_specific" "config_pre_install_distribution_specific" << 'PRE_INSTALL_DISTRIBUTION_SPECIFIC'
*give config a chance to act before install_distribution_specific*
Called after `create_rootfs_cache` (_prepare basic rootfs: unpack cache or create from scratch_) but before `install_distribution_specific` (_install distribution and board specific applications_).
PRE_INSTALL_DISTRIBUTION_SPECIFIC

	# stage: install kernel and u-boot packages
	# install distribution and board specific applications

	LOG_SECTION="distro" do_with_logging install_distribution_specific
	LOG_SECTION="install_common" do_with_logging install_distribution_agnostic

	# install locally built packages
	[[ $EXTERNAL_NEW == compile ]] && LOG_SECTION="packages_local" do_with_logging chroot_installpackages_local

	# install from apt.armbian.com
	[[ $EXTERNAL_NEW == prebuilt ]] && LOG_SECTION="packages_prebuilt" do_with_logging chroot_installpackages "yes"

	# stage: user customization script
	# NOTE: installing too many packages may fill tmpfs mount
	LOG_SECTION="custom" do_with_logging customize_image

	# remove packages that are no longer needed. rootfs cache + uninstall might have leftovers.
	LOG_SECTION="rootfs_apt_get_autoremove" do_with_logging apt_purge_unneeded_packages

	# create list of installed packages for debug purposes
	chroot $SDCARD /bin/bash -c "dpkg --get-selections" | grep -v deinstall | awk '{print $1}' | cut -f1 -d':' > $DEST/${LOG_SUBPATH}/installed-packages-${RELEASE}$([[ ${BUILD_MINIMAL} == yes ]] && echo "-minimal")$([[ ${BUILD_DESKTOP} == yes ]] && echo "-desktop").list.log 2>&1

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
		LOG_SECTION="partitioning" do_with_logging prepare_partitions
		LOG_SECTION="image" do_with_logging create_image_from_sdcard_rootfs
	fi

	# stage: unmount tmpfs
	umount $SDCARD 2>&1
	if [[ $use_tmpfs = yes ]]; then
		while grep -qs "$SDCARD" /proc/mounts; do
			umount $SDCARD
			sleep 5
		done
	fi
	rm -rf $SDCARD

	# remove exit trap
	trap - INT TERM EXIT
}
