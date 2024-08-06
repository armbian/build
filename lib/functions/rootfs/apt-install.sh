#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function apt_purge_unneeded_packages_and_clean_apt_caches() {
	# remove packages that are no longer needed. rootfs cache + uninstall might have leftovers.
	display_alert "No longer needed packages" "purge" "info"
	chroot_sdcard_apt_get autoremove

	declare dir_var_lib_apt_lists="/var/lib/apt/lists"
	declare dir_var_cache_apt="/var/cache/apt"
	declare -i dir_var_cache_apt_file_count dir_var_lib_apt_lists_file_count

	# Now, let's list what is under ${SDCARD}/var/cache/apt -- it should be empty. If it isn't, warn, and clean it up.
	dir_var_cache_apt_file_count="$(find "${SDCARD}${dir_var_cache_apt}" -type f | wc -l)"
	if [[ "${dir_var_cache_apt_file_count}" -gt 1 ]]; then # there is sometimes at least one file, the lock file
		display_alert "SDCARD ${dir_var_cache_apt} is not empty" "${dir_var_cache_apt} :: ${dir_var_cache_apt_file_count} files" "wrn"
		run_host_command_logged ls -lahtR "${SDCARD}${dir_var_cache_apt}"
		wait_for_disk_sync "after listing ${SDCARD}${dir_var_cache_apt}"
	else
		display_alert "SDCARD ${dir_var_cache_apt} is empty" "${dir_var_cache_apt} :: ${dir_var_cache_apt_file_count} files" "debug"
	fi

	# attention: this is _very different_ from `chroot_sdcard_apt_get clean` (which would clean the cache)
	chroot_sdcard apt-get clean
	wait_for_disk_sync "after apt-get clean"

	# Also clean ${SDCARD}/var/lib/apt/lists; this is where the package lists are stored.
	dir_var_lib_apt_lists_file_count="$(find "${SDCARD}${dir_var_lib_apt_lists}" -type f | wc -l)"
	if [[ "${dir_var_lib_apt_lists_file_count}" -gt 1 ]]; then # there is sometimes at least one file, the lock file
		display_alert "SDCARD ${dir_var_lib_apt_lists} is not empty" "${dir_var_lib_apt_lists} :: ${dir_var_lib_apt_lists_file_count} files" "wrn"
		run_host_command_logged ls -lahtR "${SDCARD}${dir_var_lib_apt_lists}"
		wait_for_disk_sync "after listing ${SDCARD}${dir_var_cache_apt}"
	else
		display_alert "SDCARD ${dir_var_lib_apt_lists} is empty" "${dir_var_lib_apt_lists} :: ${dir_var_lib_apt_lists_file_count} files" "debug"
	fi

	# Either way, clean it away, we don't wanna ship those lists on images or rootfs.
	run_host_command_logged rm -rf "${SDCARD}${dir_var_lib_apt_lists}"
	wait_for_disk_sync "after cleaning ${SDCARD}${dir_var_lib_apt_lists}"
}

function apt_lists_copy_from_host_to_image_and_update() {
	display_alert "Copying host-side apt list cache into image" "apt-get update and clean image-side" "info"

	declare -i local_apt_cache_lists_count
	if [[ "${LOCAL_APT_CACHE_INFO[USE]}" == "yes" ]]; then
		# If using a host-side local cache, copy the lists into the image...
		run_host_command_logged mkdir -pv "${LOCAL_APT_CACHE_INFO[SDCARD_LISTS_DIR]}"
		display_alert "Copying host-side local apt list cache dir" "${LOCAL_APT_CACHE_INFO[SDCARD_LISTS_DIR]}" "debug"
		run_host_command_logged cp -pr "${LOCAL_APT_CACHE_INFO[HOST_LISTS_DIR]}"/* "${LOCAL_APT_CACHE_INFO[SDCARD_LISTS_DIR]}"/

		# Count how many files we have in the lists dir.
		local_apt_cache_lists_count="$(ls -1 "${LOCAL_APT_CACHE_INFO[SDCARD_LISTS_DIR]}" | wc -l)"
		display_alert "After copying host-side cache into image" "${local_apt_cache_lists_count} files" "info"
	fi

	# ...and update the lists in the image; this makes sure we're not shipping stale lists. also clean.
	# Attention: this is NOT using `chroot_sdcard_apt_get_update` or any `chroot_sdcard_apt_get` variant,
	#            since would actually mount the lists from the host, which is not what we want.
	display_alert "Updating apt lists in image" "apt-get update and clean" "info"
	chroot_sdcard apt-get -y -o "APT::Get::List-Cleanup=1" -o "APT::Clean-Installed=1" update
	chroot_sdcard apt-get -y -o "APT::Get::List-Cleanup=1" -o "APT::Clean-Installed=1" clean

	local_apt_cache_lists_count="$(ls -1 "${LOCAL_APT_CACHE_INFO[SDCARD_LISTS_DIR]}" | wc -l)"
	display_alert "After updating and cleaning image apt list cache" "${local_apt_cache_lists_count} files" "info"
}

# this is called:
# 1) install_deb_chroot "${DEB_STORAGE}/somethingsomething.deb" (yes, it's always ${DEB_STORAGE})
function install_deb_chroot() {
	local package="$1"
	local variant="$2"
	local transfer="$3"
	local install_target="${package}"
	local log_extra=" from repository"
	local package_filename
	package_filename="$(basename "${package}")"

	# For the local case.
	if [[ "${variant}" != "remote" ]]; then
		log_extra=""
	fi
	display_alert "Installing${log_extra}: ${package}" "${package_filename}" "debinstall" # This needs its own level

	if [[ "${variant}" != "remote" ]]; then
		# @TODO: this can be sped up significantly by mounting debs readonly directly in chroot /root/debs and installing from there
		# also won't require cleanup later

		install_target="/root/${package_filename}"
		if [[ ! -f "${SDCARD}${install_target}" ]]; then
			display_alert "Copying ${package_filename}" "'${package}' -> '${SDCARD}${install_target}'" "debug"
			run_host_command_logged cp -pv "${package}" "${SDCARD}${install_target}"
		fi
	fi

	# install in chroot via apt-get, not dpkg, so dependencies are also installed from repo if needed.
	declare -g if_error_detail_message="Installation of $install_target failed ${BOARD} ${RELEASE} ${BUILD_DESKTOP} ${LINUXFAMILY}"
	declare -a extra_apt_envs=()
	extra_apt_envs+=("ARMBIAN_IMAGE_BUILD_BOOTFS_TYPE=${BOOTFS_TYPE:-"unset"}")                             # used by package postinst scripts to bevahe
	DONT_MAINTAIN_APT_CACHE="yes" chroot_sdcard_apt_get --no-install-recommends install "${install_target}" # don't auto-maintain apt cache when installing from packages.
	unset extra_apt_envs

	# IMPORTANT! Do not use short-circuit above as last statement in a function, since it determines the result of the function.
	return 0
}

function install_artifact_deb_chroot() {
	declare deb_name="$1"
	declare -A -g image_artifacts_debs_reversioned # global associative array
	declare revisioned_deb_rel_path="${image_artifacts_debs_reversioned["${deb_name}"]}"
	if [[ -z "${revisioned_deb_rel_path}" ]]; then
		exit_with_error "No revisioned deb path found for '${deb_name}'"
	fi
	display_alert "Installing artifact deb" "${deb_name} :: ${revisioned_deb_rel_path}" "debug"
	install_deb_chroot "${DEB_STORAGE}/${revisioned_deb_rel_path}"

	# Mark the deb as installed in the global associative array.
	declare -A -g image_artifacts_debs_installed
	image_artifacts_debs_installed["${deb_name}"]="yes"
	debug_dict image_artifacts_debs_installed
}
