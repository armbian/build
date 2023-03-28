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
	# check artifact_name is set otherwise exit_with_error
	[[ -z "${artifact_name}" ]] && exit_with_error "fakeroot_dpkg_deb_build: artifact_name is not set"

	display_alert "Building .deb package" "${artifact_name}: $*" "debug"

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

	# Get the basename of the dir
	declare pkg_name
	pkg_name=$(basename "${first_arg}")

	# Show the total human size of the source package directory.
	display_alert "Source package size" "${first_arg}: $(du -sh "${first_arg}" | cut -f1)" "debug"

	# find the DEBIAN scripts (postinst, prerm, etc) and run shellcheck on them.
	dpkg_deb_run_shellcheck_on_scripts "${first_arg}"

	# Debug, dump the generated postrm/preinst/postinst
	if [[ "${SHOW_DEBUG}" == "yes" || "${SHOW_DEBIAN}" == "yes" ]]; then
		# Dump the CONTROL file to the log (always, @TODO later under debugging)
		run_tool_batcat --file-name "${artifact_name}/DEBIAN/control" "${first_arg}/DEBIAN/control"

		if [[ -f "${first_arg}/DEBIAN/changelog" ]]; then
			run_tool_batcat --file-name "${artifact_name}/DEBIAN/changelog" "${first_arg}/DEBIAN/changelog"
		fi

		if [[ -f "${first_arg}/DEBIAN/postrm" ]]; then
			run_tool_batcat --file-name "${artifact_name}/DEBIAN/postrm.sh" "${first_arg}/DEBIAN/postrm"
		fi

		if [[ -f "${first_arg}/DEBIAN/preinst" ]]; then
			run_tool_batcat --file-name "${artifact_name}/DEBIAN/preinst.sh" "${first_arg}/DEBIAN/preinst"
		fi

		if [[ -f "${first_arg}/DEBIAN/postinst" ]]; then
			run_tool_batcat --file-name "${artifact_name}/DEBIAN/postinst.sh" "${first_arg}/DEBIAN/postinst"
		fi
	fi

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

function artifact_package_hook_helper_board_side_functions() {
	declare script="${1}"
	shift
	# each remaining arg is a function name; for each, run 'declare -f', remove the first, second and last line (function declaration, open brace, close brac, and add it to contents.
	declare -a functions=("$@")
	declare contents=""
	declare newline=$'\n'
	for function in "${functions[@]}"; do
		contents+="${newline}## begin contents of '${function}'${newline}"
		contents+="$(declare -f "${function}" | sed -e '2d' -e '1d' -e '$d')"
		contents+="${newline}## end contents of '${function}'${newline}"
	done
	generic_artifact_package_hook_helper "${script}" "${contents}"
}

function generic_artifact_package_hook_helper() {
	# check '$destination' is set
	[[ -z "${destination}" ]] && exit_with_error "generic_artifact_package_hook_helper: destination not set"
	declare script="${1}"
	declare contents="${2}"
	declare package_DEBIAN_dir="${destination}"/DEBIAN
	[[ ! -d "${package_DEBIAN_dir}" ]] && exit_with_error "generic_artifact_package_hook_helper: package DEBIAN dir '${package_DEBIAN_dir}' doesn't exist"

	cat >> "${package_DEBIAN_dir}/${script}" <<- EOT
		#!/bin/bash
		echo "Armbian '${artifact_name:?}' for '${artifact_version:?}': '${script}' starting."
		set +e # NO ERROR CONTROL, for compatibility with legacy Armbian scripts.
		set -x # Debugging

		$(echo "${contents}")

		set +x # Disable debugging
		echo "Armbian '${artifact_name:?}' for '${artifact_version:?}': '${script}' finishing."
		true
	EOT
	chmod 755 "${package_DEBIAN_dir}/${script}"

	# produce log asset for script (@TODO: batcat?)
	LOG_ASSET="deb-${artifact_name:?}-${script}.sh" do_with_log_asset run_host_command_logged cat "${package_DEBIAN_dir}/${script}"
}
