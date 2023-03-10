#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

compile_plymouth_theme_armbian() {

	declare cleanup_id="" tmp_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "deb-armbian-plymouth-theme" cleanup_id tmp_dir # namerefs

	declare plymouth_theme_armbian_dir=armbian-plymouth-theme_${REVISION}_all
	display_alert "Building deb" "armbian-plymouth-theme" "info"

	run_host_command_logged mkdir -p "${tmp_dir}/${plymouth_theme_armbian_dir}"/{DEBIAN,usr/share/plymouth/themes/armbian}

	# set up control file
	cat <<- END > "${tmp_dir}/${plymouth_theme_armbian_dir}"/DEBIAN/control
		Package: armbian-plymouth-theme
		Version: $REVISION
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Depends: plymouth, plymouth-themes
		Section: universe/x11
		Priority: optional
		Description: boot animation, logger and I/O multiplexer - Armbian theme
	END

	run_host_command_logged cp "${SRC}"/packages/plymouth-theme-armbian/debian/{postinst,prerm,postrm} \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/DEBIAN/
	chmod 755 "${tmp_dir}/${plymouth_theme_armbian_dir}"/DEBIAN/{postinst,prerm,postrm}

	# this requires `imagemagick`

	run_host_command_logged convert -resize 256x256 \
		"${SRC}"/packages/plymouth-theme-armbian/armbian-logo.png \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/usr/share/plymouth/themes/armbian/bgrt-fallback.png

	run_host_command_logged convert -resize 52x52 \
		"${SRC}"/packages/plymouth-theme-armbian/spinner.gif \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/usr/share/plymouth/themes/armbian/throbber-%04d.png

	run_host_command_logged cp "${SRC}"/packages/plymouth-theme-armbian/watermark.png \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/usr/share/plymouth/themes/armbian/

	run_host_command_logged cp "${SRC}"/packages/plymouth-theme-armbian/{bullet,capslock,entry,keyboard,keymap-render,lock}.png \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/usr/share/plymouth/themes/armbian/

	run_host_command_logged cp "${SRC}"/packages/plymouth-theme-armbian/armbian.plymouth \
		"${tmp_dir}/${plymouth_theme_armbian_dir}"/usr/share/plymouth/themes/armbian/

	fakeroot_dpkg_deb_build "${tmp_dir}/${plymouth_theme_armbian_dir}"

	run_host_command_logged rsync --remove-source-files -rq "${tmp_dir}/${plymouth_theme_armbian_dir}.deb" "${DEB_STORAGE}/"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}
