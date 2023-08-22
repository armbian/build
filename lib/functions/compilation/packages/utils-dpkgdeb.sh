#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# for RAW deb building. does a bunch of magic to "DEBIAN" directory. Arguments are the open package directory and the artifact_deb_id
function fakeroot_dpkg_deb_build() {
	# check artifact_name and artifact_version is set otherwise exit_with_error
	[[ -z "${artifact_name}" ]] && exit_with_error "fakeroot_dpkg_deb_build: artifact_name is not set"
	[[ -z "${artifact_version}" ]] && exit_with_error "fakeroot_dpkg_deb_build: artifact_version is not set"
	[[ -z "${artifact_deb_repo}" ]] && exit_with_error "fakeroot_dpkg_deb_build: artifact_deb_repo is not set"

	display_alert "Building .deb package" "${artifact_name}: $*" "debug"

	declare package_directory="${1}"
	declare artifact_deb_id="${2}"

	if [[ ! -d "${package_directory}" ]]; then
		exit_with_error "fakeroot_dpkg_deb_build: can't find source package directory: ${package_directory}"
	fi

	# Check artifact_deb_id is set and not empty
	if [[ -z "${artifact_deb_id}" ]]; then
		exit_with_error "fakeroot_dpkg_deb_build: artifact_deb_id (2nd parameter) is not set, called with package_directory: '${package_directory}'"
	fi

	# Obtain from the globals
	declare -A -g artifact_map_packages
	declare -A -g artifact_map_debs
	debug_dict artifact_map_packages
	debug_dict artifact_map_debs
	declare artifact_deb_package="${artifact_map_packages[${artifact_deb_id}]}"
	declare artifact_deb_rel_path="${artifact_map_debs[${artifact_deb_id}]}"

	# If either is empty, bomb
	if [[ -z "${artifact_deb_package}" ]]; then
		exit_with_error "fakeroot_dpkg_deb_build: artifact_deb_package (artifact_map_packages) is not set or found for '${artifact_deb_id}'"
	fi
	if [[ -z "${artifact_deb_rel_path}" ]]; then
		exit_with_error "fakeroot_dpkg_deb_build: artifact_deb_rel_path (artifact_map_debs) is not set or found for '${artifact_deb_id}'"
	fi

	# Show the total human size of the source package directory.
	display_alert "Source package size" "${package_directory}: $(du -sh "${package_directory}" | cut -f1)" "debug"

	# Lets fix all packages with Installed-Size:
	# get the size of the package in bytes
	declare -i pkg_size_bytes
	pkg_size_bytes=$(du -s -b "${package_directory}" | cut -f1)
	# edit DEBIAN/control, removed any Installed-Size: line
	sed -i '/^Installed-Size:/d' "${package_directory}/DEBIAN/control"
	# add the new Installed-Size: line. The disk space is given as the integer value of the estimated installed size in bytes, divided by 1024 and rounded up.
	declare -i installed_size
	installed_size=$(((pkg_size_bytes + 1023) / 1024))
	echo "Installed-Size: ${installed_size}" >> "${package_directory}/DEBIAN/control"

	# Lets create DEBIAN/md5sums, for all the files in ${package_directory}. Do not include the paths in the md5sums file. Don't include the DEBIAN/* files.
	find "${package_directory}" -type f -not -path "${package_directory}/DEBIAN/*" -print0 | xargs -0 md5sum | sed "s|${package_directory}/||g" > "${package_directory}/DEBIAN/md5sums"

	# Parse the DEBIAN/control and get the real package name...
	declare control_package_name
	control_package_name=$(grep -E "^Package:" "${package_directory}/DEBIAN/control" | cut -d' ' -f2)

	# generate minimal DEBIAN/changelog
	cat <<- EOF > "${package_directory}"/DEBIAN/changelog
		${control_package_name} (${artifact_version}) ${artifact_deb_repo}; urgency=low

		  * Initial changelog entry for ${control_package_name} package hash ${artifact_version}

		 -- $MAINTAINER <$MAINTAINERMAIL>  $(date -R)
	EOF

	# Also a usr/share/doc/${control_package_name}/changelog.gz
	mkdir -p "${package_directory}/usr/share/doc/${control_package_name}"
	gzip -9 -c "${package_directory}/DEBIAN/changelog" > "${package_directory}/usr/share/doc/${control_package_name}/changelog.gz"

	# find the DEBIAN scripts (postinst, prerm, etc) and run shellcheck on them.
	dpkg_deb_run_shellcheck_on_scripts "${package_directory}"

	# Debug, dump the generated postrm/preinst/postinst
	if [[ "${SHOW_DEBUG}" == "yes" || "${SHOW_DEBIAN}" == "yes" ]]; then
		# Dump the CONTROL file to the log
		run_tool_batcat --file-name "${artifact_name}/DEBIAN/control" "${package_directory}/DEBIAN/control"

		if [[ -f "${package_directory}/DEBIAN/changelog" ]]; then
			run_tool_batcat --file-name "${artifact_name}/DEBIAN/changelog" "${package_directory}/DEBIAN/changelog"
		fi

		if [[ -f "${package_directory}/DEBIAN/postrm" ]]; then
			run_tool_batcat --file-name "${artifact_name}/DEBIAN/postrm.sh" "${package_directory}/DEBIAN/postrm"
		fi

		if [[ -f "${package_directory}/DEBIAN/preinst" ]]; then
			run_tool_batcat --file-name "${artifact_name}/DEBIAN/preinst.sh" "${package_directory}/DEBIAN/preinst"
		fi

		if [[ -f "${package_directory}/DEBIAN/postinst" ]]; then
			run_tool_batcat --file-name "${artifact_name}/DEBIAN/postinst.sh" "${package_directory}/DEBIAN/postinst"
		fi

		run_tool_batcat --file-name "${artifact_name}/DEBIAN/md5sums" "${package_directory}/DEBIAN/md5sums"
	fi

	declare deb_final_filename="${PACKAGES_HASHED_STORAGE}/${artifact_deb_rel_path}"
	declare deb_final_dir
	deb_final_dir=$(dirname "${deb_final_filename}")

	mkdir -p "${deb_final_dir}"
	display_alert "Building package, this might take a while.." "${deb_final_filename/*\//}" info
	run_host_command_logged_raw fakeroot dpkg-deb -b "-Z${DEB_COMPRESS}" "${package_directory}" "${deb_final_filename}"
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
		#set -e # Debugging

		$(echo "${contents}")

		set +x # Disable debugging
		echo "Armbian '${artifact_name:?}' for '${artifact_version:?}': '${script}' finishing."
		true
	EOT
	chmod 755 "${package_DEBIAN_dir}/${script}"

	# produce log asset for script (@TODO: batcat?)
	LOG_ASSET="deb-${artifact_name:?}-${script}.sh" do_with_log_asset run_host_command_logged cat "${package_DEBIAN_dir}/${script}"
}
