#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function compile_fake_ubuntu_advantage_tools() {
	: "${artifact_version:?artifact_version is not set}"

	display_alert "Generating fake ubuntu advantage tools package" "@host" "info"

	declare cleanup_id="" fw_temp_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "deb-fake_ubuntu_advantage_tools" cleanup_id fw_temp_dir # namerefs

	declare fw_dir="fake_ubuntu_advantage_tools"
	mkdir -p "${fw_temp_dir}/${fw_dir}"

	cd "${fw_temp_dir}/${fw_dir}" || exit_with_error "can't change directory"

	# set up control file
	mkdir -p DEBIAN
	cat <<- END > DEBIAN/control
		Package: fake-ubuntu-advantage-tools
		Version: ${artifact_version}
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Installed-Size: 1
		Conflicts: ubuntu-advantage-tools
		Breaks: ubuntu-advantage-tools
		Provides: ubuntu-advantage-tools (= 65535)
		Description: Ban ubuntu-advantage-tools while satisfying ubuntu-minimal dependency
	END

	cd "${fw_temp_dir}" || exit_with_error "can't change directory"

	# package, directly to DEB_STORAGE; full version might be very big for tmpfs.
	display_alert "Building fake Ubuntu advantage tools package" "fake_ubuntu_advantage_tools" "info"
	fakeroot_dpkg_deb_build "fake_ubuntu_advantage_tools" "${DEB_STORAGE}"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}
