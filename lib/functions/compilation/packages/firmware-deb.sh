#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function compile_firmware() {
	: "${artifact_version:?artifact_version is not set}"

	display_alert "Merging and packaging linux firmware" "@host --> firmware${FULL}" "info"

	declare cleanup_id="" fw_temp_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "deb-firmware${FULL}" cleanup_id fw_temp_dir # namerefs

	declare fw_dir="armbian-firmware${FULL}"
	mkdir -p "${fw_temp_dir}/${fw_dir}/lib/firmware"

	local ARMBIAN_FIRMWARE_GIT_SOURCE="${ARMBIAN_FIRMWARE_GIT_SOURCE:-"https://github.com/armbian/firmware"}"
	local ARMBIAN_FIRMWARE_GIT_BRANCH="${ARMBIAN_FIRMWARE_GIT_BRANCH:-"master"}"

	# Fetch Armbian firmware from git.
	declare fetched_revision
	do_checkout="no" fetch_from_repo "${ARMBIAN_FIRMWARE_GIT_SOURCE}" "armbian-firmware-git" "branch:${ARMBIAN_FIRMWARE_GIT_BRANCH}"
	declare -r armbian_firmware_git_sha1="${fetched_revision}"

	declare extra_conflicts_comma=""
	if [[ -n $FULL ]]; then
		# Fetch kernel firmware from git. This is large, but we don't have two copies of it anymore. So more manageable.
		declare fetched_revision
		do_checkout="no" fetch_from_repo "$MAINLINE_FIRMWARE_SOURCE" "linux-firmware-git" "branch:main"
		declare -r mainline_firmware_git_sha1="${fetched_revision}"

		# use git archive to export the ${mainline_firmware_git_sha1} revision into "${fw_temp_dir}/${fw_dir}/lib/firmware/"
		run_host_command_logged git -C "${SRC}/cache/sources/linux-firmware-git" archive --format=tar "${mainline_firmware_git_sha1}" "|" tar -C "${fw_temp_dir}/${fw_dir}/lib/firmware/" -xf -

		# Full version conflicts with more stuff, of course.
		extra_conflicts_comma=",amd64-microcode,intel-microcode"

		# @TODO: rpardini: disabled, this is not the place to do this; move to extension/bsp/whatever
		# cp : create hardlinks for ath11k WCN685x hw2.1 firmware since they are using the same firmware with hw2.0
		# run_host_command_logged cp -af --reflink=auto "${fw_temp_dir}/${fw_dir}/lib/firmware/ath11k/WCN6855/hw2.0/" "${fw_temp_dir}/${fw_dir}/lib/firmware/ath11k/WCN6855/hw2.1/"
	fi

	# Armbian firmware; this overwrites anything in the mainline firmware repo (if that was included, in the full version only)
	run_host_command_logged git -C "${SRC}/cache/sources/armbian-firmware-git" archive --format=tar "${armbian_firmware_git_sha1}" "|" tar -C "${fw_temp_dir}/${fw_dir}/lib/firmware/" -xf -

	# Show the size of the firmware directory in a tree if debugging
	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		run_host_command_logged tree -C --du -h -L 1 "${fw_temp_dir}/${fw_dir}"/lib/firmware "|| true" # do not fail
	fi

	cd "${fw_temp_dir}/${fw_dir}" || exit_with_error "can't change directory"

	# set up control file
	mkdir -p DEBIAN
	# @TODO: rpardini: this needs Conflicts: with the standard Ubuntu/Debian linux-firmware packages and other firmware pkgs in Debian
	cat <<- END > DEBIAN/control
		Package: armbian-firmware${FULL}
		Version: ${artifact_version}
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Installed-Size: 1
		Conflicts: linux-firmware, firmware-brcm80211, firmware-ralink, firmware-samsung, firmware-realtek, armbian-firmware${REPLACE}${extra_conflicts_comma}
		Provides: linux-firmware, firmware-brcm80211, firmware-ralink, firmware-samsung, firmware-realtek, armbian-firmware${REPLACE}${extra_conflicts_comma}
		Section: kernel
		Priority: optional
		Description: Armbian - Linux firmware${FULL}
	END

	cd "${fw_temp_dir}" || exit_with_error "can't change directory"

	# package, directly to DEB_STORAGE; full version might be very big for tmpfs.
	display_alert "Building firmware package" "armbian-firmware${FULL}" "info"
	fakeroot_dpkg_deb_build "armbian-firmware${FULL}" "${DEB_STORAGE}"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}
