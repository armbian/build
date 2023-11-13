#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function build_rootfs_and_image() {
	display_alert "Checking for rootfs cache" "$(echo "${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}" | tr -s " ")" "info"

	# get a basic rootfs, either from cache or from scratch
	get_or_create_rootfs_cache_chroot_sdcard # only occurrence of this; has its own logging sections

	# stage: with a basic rootfs available, we mount the chroot and work on it
	LOG_SECTION="mount_chroot_sdcard" do_with_logging mount_chroot "${SDCARD}"

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

	# Deploy the full apt lists, including the Armbian repo.
	create_sources_list_and_deploy_repo_key "image-late" "${RELEASE}" "${SDCARD}/"

	# remove packages that are no longer needed. rootfs cache + uninstall might have leftovers.
	LOG_SECTION="apt_purge_unneeded_packages_and_clean_apt_caches" do_with_logging apt_purge_unneeded_packages_and_clean_apt_caches

	# for IMAGES (not the rootfs cache!), we wanna ship a valid /var/lib/apt/lists.
	# copy it over from the host-side cache into the image, and run a final apt-get update+clean, to clean off what is not needed for this specific image.
	LOG_SECTION="apt_lists_copy_from_host_to_image_and_update" do_with_logging apt_lists_copy_from_host_to_image_and_update

	# creating xapian index that synaptic runs faster
	if [[ "${BUILD_DESKTOP}" == yes && -f "${SDCARD}/usr/sbin/update-apt-xapian-index" ]]; then
		display_alert "Recreating Synaptic search index" "Please wait - updating Xapian index for image" "info"
		chroot_sdcard "/usr/sbin/update-apt-xapian-index -u"
	fi

	# for reference, debugging / sanity checking
	LOG_SECTION="list_installed_packages" do_with_logging list_installed_packages

	LOG_SECTION="post_debootstrap_tweaks" do_with_logging post_debootstrap_tweaks

	# clean up / prepare for making the image
	LOG_SECTION="umount_chroot_sdcard" do_with_logging umount_chroot "${SDCARD}"

	# obtain the size, in MiB, of "${SDCARD}" at this point.
	declare -i rootfs_size_mib
	rootfs_size_mib=$(du --apparent-size -sm "${SDCARD}" | awk '{print $1}')
	display_alert "Actual rootfs size" "${rootfs_size_mib}MiB" ""

	# warn if rootfs_size_mib is higher than the tmpfs_estimated_size
	if [[ ${rootfs_size_mib} -gt ${tmpfs_estimated_size} ]]; then
		display_alert "Rootfs post-tweaks size is larger than estimated tmpfs size" "${rootfs_size_mib}MiB > ${tmpfs_estimated_size}MiB" "wrn"
	fi

	# ------------------------------------ UP HERE IT's 'rootfs' stuff -------------------------------

	#------------------------------------ DOWN HERE IT's 'image' stuff -------------------------------

	LOG_SECTION="prepare_partitions" do_with_logging prepare_partitions
	LOG_SECTION="create_image_from_sdcard_rootfs" do_with_logging create_image_from_sdcard_rootfs

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

	# Loop over dict image_artifacts_packages_version (package_name -> package version), and warn if any installed versions don't match.
	# This is a sanity check, to make sure that the packages we installed are the ones we expected to install.
	# Things that might disrupt this: apt repos containing random versions that are then apt upgraded, forced install, crazy customize, wrong pinning, etc.
	declare -g -A image_artifacts_packages_version # global scope, set in main_default_build_packages()
	declare -g -A image_artifacts_debs_installed   # global scope, set in main_default_build_packages()
	declare -g -A image_artifacts_packages         # global scope, set in main_default_build_packages()

	declare artifact_deb_id pkg_name pkg_wanted_version
	for artifact_deb_id in "${!image_artifacts_debs_installed[@]}"; do
		declare deb_is_installed_in_image="${image_artifacts_debs_installed["${artifact_deb_id}"]}"
		if [[ "${deb_is_installed_in_image}" != "yes" ]]; then
			continue # skip packages that are not actually installed (eg: kernel-headers, transitional bsp-cli, etc)
		fi
		pkg_name="${image_artifacts_packages["${artifact_deb_id}"]}"
		pkg_wanted_version="${image_artifacts_packages_version[${pkg_name}]}" # this is the hash-version
		display_alert "Checking installed version of package" "${pkg_name}=${pkg_wanted_version}" "debug"
		declare actual_version
		actual_version=$(chroot "${SDCARD}" dpkg-query -W -f='${Status} ${Package} ${Armbian-Original-Hash}\n' "${pkg_name}" | grep " ok installed" | cut -d " " -f 5)
		if [[ "${actual_version}" != "${pkg_wanted_version}" ]]; then
			declare dpkg_status
			dpkg_status=$(chroot "${SDCARD}" dpkg-query -W -f='${Status} ${Package} ${Armbian-Original-Hash}\n' "${pkg_name}" || true)
			display_alert "Installed hash of package does not match wanted hash. Check for inconsistent repo, customize.sh/hooks, extensions, or upgrades installing wrong version" "${pkg_name} :: actual:'${actual_version}' wanted:'${pkg_wanted_version}'; status: '${dpkg_status}'" "warn"
		else
			display_alert "Image installed package hash" "✅ ${pkg_name} = ${actual_version}" "info"
		fi
	done
}
