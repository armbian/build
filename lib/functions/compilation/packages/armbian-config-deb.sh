#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

compile_armbian-config() {
	: "${artifact_version:?artifact_version is not set}"

	display_alert "Generating armbian-config package" "@host" "info"

	declare cleanup_id="" tmp_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "deb-armbian-config" cleanup_id tmp_dir # namerefs

	declare armbian_config_dir="armbian-config"
	mkdir -p "${tmp_dir}/${armbian_config_dir}"

	local ARMBIAN_CONFIG_GIT_SOURCE="${ARMBIAN_FIRMWARE_GIT_SOURCE:-"https://github.com/armbian/config"}"
	local ARMBIAN_CONFIG_GIT_BRANCH="${ARMBIAN_FIRMWARE_GIT_BRANCH:-"master"}"

	fetch_from_repo "https://github.com/armbian/config" "armbian-config" "branch:master"
	# this is also not getting any updates
	fetch_from_repo "https://github.com/dylanaraps/neofetch" "neofetch" "tag:7.1.0"

	# Fetch Armbian config from git.
	declare fetched_revision
	do_checkout="no" fetch_from_repo "${ARMBIAN_CONFIG_GIT_SOURCE}" "armbian-config-git" "branch:${ARMBIAN_CONFIG_GIT_BRANCH}"
	declare -r armbian_firmware_git_sha1="${fetched_revision}"

	# @TODO: move this to where it is actually used; not everyone needs to pull this in
	fetch_from_repo "$GITHUB_SOURCE/complexorganizations/wireguard-manager" "wireguard-manager" "branch:main"

	mkdir -p "${tmp_dir}/${armbian_config_dir}"/{DEBIAN,usr/bin/,usr/sbin/,usr/lib/armbian-config/}

	cd "${tmp_dir}/${armbian_config_dir}" || exit_with_error "can't change directory"

	# set up control file
	cat <<- END > DEBIAN/control
		Package: armbian-config
		Version: ${artifact_version}
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Replaces: armbian-bsp, neofetch
		Depends: bash, iperf3, psmisc, curl, bc, expect, dialog, pv, zip, debconf-utils, unzip, build-essential, html2text, html2text, dirmngr, software-properties-common, debconf, jq
		Recommends: armbian-bsp
		Suggests: libpam-google-authenticator, qrencode, network-manager, sunxi-tools
		Section: utils
		Priority: optional
		Description: Armbian configuration utility
	END

	install -m 755 "${SRC}"/cache/sources/neofetch/neofetch "${tmp_dir}/${armbian_config_dir}"/usr/bin/neofetch
	cd "${tmp_dir}/${armbian_config_dir}"/usr/bin/ || exit_with_error "Failed to cd to ${tmp_dir}/${armbian_config_dir}/usr/bin/"
	process_patch_file "${SRC}/patch/misc/add-armbian-neofetch.patch" "applying"

	install -m 755 "${SRC}"/cache/sources/wireguard-manager/wireguard-manager.sh "${tmp_dir}/${armbian_config_dir}"/usr/bin/wireguard-manager
	install -m 755 "${SRC}"/cache/sources/armbian-config/scripts/tv_grab_file "${tmp_dir}/${armbian_config_dir}"/usr/bin/tv_grab_file
	install -m 755 "${SRC}"/cache/sources/armbian-config/debian-config "${tmp_dir}/${armbian_config_dir}"/usr/sbin/armbian-config
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-jobs "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/jobs.sh
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-submenu "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/submenu.sh
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-functions "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/functions.sh
	install -m 644 "${SRC}"/cache/sources/armbian-config/debian-config-functions-network "${tmp_dir}/${armbian_config_dir}"/usr/lib/armbian-config/functions-network.sh
	install -m 755 "${SRC}"/cache/sources/armbian-config/softy "${tmp_dir}/${armbian_config_dir}"/usr/sbin/softy
	# fallback to replace armbian-config in BSP
	ln -sf /usr/sbin/armbian-config "${tmp_dir}/${armbian_config_dir}"/usr/bin/armbian-config
	ln -sf /usr/sbin/softy "${tmp_dir}/${armbian_config_dir}"/usr/bin/softy

	fakeroot_dpkg_deb_build "${tmp_dir}/${armbian_config_dir}" "${DEB_STORAGE}"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early

}
