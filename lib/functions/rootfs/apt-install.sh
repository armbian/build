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
	declare -i dir_var_cache_apt_size_mb dir_var_cache_apt_size_after_cleaning_mb dir_var_lib_apt_lists_size_mb

	# Now, let's list what is under ${SDCARD}/var/cache/apt -- it should be empty. If it isn't, warn, and clean it up.
	dir_var_cache_apt_size_mb="$(du -sm "${SDCARD}${dir_var_cache_apt}" | cut -f1)"
	if [[ "${dir_var_cache_apt_size_mb}" -gt 0 ]]; then
		display_alert "SDCARD ${dir_var_cache_apt} is not empty" "${dir_var_cache_apt} :: ${dir_var_cache_apt_size_mb}MB" "wrn"
		# list the contents
		run_host_command_logged ls -lahtR "${SDCARD}${dir_var_cache_apt}"
		wait_for_disk_sync "after listing ${SDCARD}${dir_var_cache_apt}"
	else
		display_alert "SDCARD ${dir_var_cache_apt} is empty" "${dir_var_cache_apt} :: ${dir_var_cache_apt_size_mb}MB" "debug"
	fi

	# attention: this is _very different_ from `chroot_sdcard_apt_get clean` (which would clean the cache)
	chroot_sdcard apt-get clean
	wait_for_disk_sync "after apt-get clean"

	dir_var_cache_apt_size_after_cleaning_mb="$(du -sm "${SDCARD}${dir_var_cache_apt}" | cut -f1)"
	display_alert "SDCARD ${dir_var_cache_apt} size after cleaning" "${dir_var_cache_apt} :: ${dir_var_cache_apt_size_after_cleaning_mb}MB" "debug"

	# Also clean ${SDCARD}/var/lib/apt/lists; this is where the package lists are stored.
	dir_var_lib_apt_lists_size_mb="$(du -sm "${SDCARD}${dir_var_lib_apt_lists}" | cut -f1)"
	if [[ "${dir_var_lib_apt_lists_size_mb}" -gt 0 ]]; then
		display_alert "SDCARD ${dir_var_lib_apt_lists} is not empty" "${dir_var_lib_apt_lists} :: ${dir_var_lib_apt_lists_size_mb}MB" "wrn"
		# list the contents
		run_host_command_logged ls -lahtR "${SDCARD}${dir_var_lib_apt_lists}"
		wait_for_disk_sync "after listing ${SDCARD}${dir_var_cache_apt}"
	else
		display_alert "SDCARD ${dir_var_lib_apt_lists} is empty" "${dir_var_lib_apt_lists} :: ${dir_var_lib_apt_lists_size_mb}MB" "debug"
	fi

	# Either way, clean it away, we don't wanna ship those lists on images or rootfs.
	run_host_command_logged rm -rf "${SDCARD}${dir_var_lib_apt_lists}"
	wait_for_disk_sync "after cleaning ${SDCARD}${dir_var_lib_apt_lists}"
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
	extra_apt_envs+=("ARMBIAN_IMAGE_BUILD_BOOTFS_TYPE=${BOOTFS_TYPE:-"unset"}") # used by package postinst scripts to bevahe
	DONT_MAINTAIN_APT_CACHE="yes" chroot_sdcard_apt_get --no-install-recommends install "${install_target}" # don't auto-maintain apt cache when installing from packages.
	unset extra_apt_envs

	# @TODO: mysterious. store installed/downloaded packages in deb storage. only used for u-boot deb. why?
	# this is some contrived way to get the uboot.deb when installing from repo; image builder needs the deb to be able to deploy uboot  later, even though it is already installed inside the chroot, it needs deb to be in host to reuse code later
	if [[ ${variant} == remote && ${transfer} == yes ]]; then
		display_alert "install_deb_chroot called with" "transfer=yes, copy WHOLE CACHE back to DEB_STORAGE, this is probably a bug" "warn"
		run_host_command_logged rsync -r "${SDCARD}"/var/cache/apt/archives/*.deb "${DEB_STORAGE}"/
	fi

	# IMPORTANT! Do not use short-circuit above as last statement in a function, since it determines the result of the function.
	return 0
}
