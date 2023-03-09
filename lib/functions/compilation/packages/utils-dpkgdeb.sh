#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# for deb building.
function fakeroot_dpkg_deb_build() {
	display_alert "Building .deb package" "$*" "debug"

	declare -a orig_args=("$@")
	# find the first non-option argument
	declare first_arg
	for first_arg in "${orig_args[@]}"; do
		if [[ "${first_arg}" != -* ]]; then
			break
		fi
	done

	if [[ ! -d "${first_arg}" ]]; then
		exit_with_error "fakeroot_dpkg_deb_build: can't find source package directory: ${first_arg}"
	fi

	# Show the total human size of the source package directory.
	display_alert "Source package size" "${first_arg}: $(du -sh "${first_arg}" | cut -f1)" "debug"

	# find the DEBIAN scripts (postinst, prerm, etc) and run shellcheck on them.
	dpkg_deb_run_shellcheck_on_scripts "${first_arg}"

	run_host_command_logged_raw fakeroot dpkg-deb -b "-Z${DEB_COMPRESS}" "${orig_args[@]}"
}

function dpkg_deb_run_shellcheck_on_scripts() {
	declare pkg_dir="$1"
	[[ -z "${pkg_dir}" ]] && exit_with_error "dpkg_deb_run_shellcheck_on_scripts: no package directory specified"
	[[ ! -d "${pkg_dir}" ]] && exit_with_error "dpkg_deb_run_shellcheck_on_scripts: pkg dir '${pkg_dir}' doesn't exist"
	[[ ! -d "${pkg_dir}/DEBIAN" ]] && exit_with_error "dpkg_deb_run_shellcheck_on_scripts: pkg dir '${pkg_dir}'/DEBIAN doesn't exist"

	# parse the DEBIAN/control script to find the name of the package
	declare pkg_name
	pkg_name=$(grep -E "^Package:" "${pkg_dir}/DEBIAN/control" | cut -d: -f2 | tr -d '[:space:]')
	[[ -z "${pkg_name}" ]] && exit_with_error "dpkg_deb_run_shellcheck_on_scripts: can't find package name in ${pkg_dir}/DEBIAN/control"

	# use "find" to find executable files in the package directory
	declare -a executables=($(find "${pkg_dir}/DEBIAN" -type f -executable || true))

	# @TODO: also include other, executable, shells scripts found in the dir; e.g. /usr/bin, /usr/sbin, etc.

	# if more than zero items in array...
	if [[ ${#executables[@]} -gt 0 ]]; then
		display_alert "Running shellcheck on package scripts" "${executables[*]}" "debug"
		if shellcheck_debian_control_scripts "${executables[@]}"; then
			display_alert "shellcheck found no problems in package scripts" "shellchecked ${#executables[@]} scripts in '${pkg_name}'" "info"
		else
			display_alert "shellcheck found problems in package scripts; see above" "shellcheck failed for '${pkg_name}'" "wrn"
		fi
	else
		display_alert "shellcheck found no problems in package scripts" "no scripts found for '${pkg_name}'" "info"
	fi
}
