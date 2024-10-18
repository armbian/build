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

	local ARMBIAN_CONFIG_GIT_SOURCE="${ARMBIAN_FIRMWARE_GIT_SOURCE:-"https://github.com/armbian/configng"}"
	local ARMBIAN_CONFIG_GIT_BRANCH="${ARMBIAN_FIRMWARE_GIT_BRANCH:-"main"}"

	# this is also not getting any updates
	fetch_from_repo "$GITHUB_SOURCE/dylanaraps/neofetch" "neofetch" "tag:7.1.0"
	fetch_from_repo "$GITHUB_SOURCE/armbian/configng" "armbian-config" "branch:main"
	fetch_from_repo "$GITHUB_SOURCE/complexorganizations/wireguard-manager" "wireguard-manager" "branch:main"

	# Fetch Armbian config from git.
	declare fetched_revision
	do_checkout="no" fetch_from_repo "${ARMBIAN_CONFIG_GIT_SOURCE}" "armbian-config-git" "branch:${ARMBIAN_CONFIG_GIT_BRANCH}"
	declare -r armbian_firmware_git_sha1="${fetched_revision}"

	# @TODO: move this to where it is actually used; not everyone needs to pull this in
	fetch_from_repo "$GITHUB_SOURCE/complexorganizations/wireguard-manager" "wireguard-manager" "branch:main"

	mkdir -p "${tmp_dir}/${armbian_config_dir}"/{DEBIAN,bin/,lib/armbian-configng/,usr/bin/}

	cd "${tmp_dir}/${armbian_config_dir}" || exit_with_error "can't change directory"

	# set up control file
	cat <<- END > DEBIAN/control
		Package: armbian-config
		Version: ${artifact_version}
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Depends: whiptail, jq
		Section: utils
		Priority: optional
		Description: Armbian configuration utility New Generation
	END

	install -m 755 "${SRC}"/cache/sources/neofetch/neofetch "${tmp_dir}/${armbian_config_dir}"/usr/bin/neofetch
	cd "${tmp_dir}/${armbian_config_dir}"/usr/bin/ || exit_with_error "Failed to cd to ${tmp_dir}/${armbian_config_dir}/usr/bin/"
	process_patch_file "${SRC}/patch/misc/add-armbian-neofetch.patch" "applying"

	# 3rd party utilities
	install -m 755 "${SRC}"/cache/sources/wireguard-manager/wireguard-manager.sh "${tmp_dir}/${armbian_config_dir}"/usr/bin/wireguard-manager

	# Armbian config parts
	install -m 755 "${SRC}"/cache/sources/armbian-config/bin/armbian-configng "${tmp_dir}/${armbian_config_dir}"/bin/armbian-configng
	cp -R "${SRC}"/cache/sources/armbian-config/lib/armbian-configng/ "${tmp_dir}/${armbian_config_dir}"/lib/

	# Linking
	ln -sf /bin/armbian-configng "${tmp_dir}/${armbian_config_dir}"/usr/bin/armbian-config

	dpkg_deb_build "${tmp_dir}/${armbian_config_dir}" "armbian-config"
	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early

}
