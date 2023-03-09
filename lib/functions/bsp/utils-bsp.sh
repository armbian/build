#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# copy_all_packages_files_for <folder> to package
copy_all_packages_files_for() {
	local package_name="${1}"

	# @TODO: rpardini: this was recovered after being assassinated by some insane person who rewrote aggregation in Python
	declare PACKAGES_SEARCH_ROOT_ABSOLUTE_DIRS="
	${SRC}/packages
	${SRC}/config/optional/_any_board/_packages
	${SRC}/config/optional/architectures/${ARCH}/_packages
	${SRC}/config/optional/families/${LINUXFAMILY}/_packages
	${SRC}/config/optional/boards/${BOARD}/_packages
	"

	for package_src_dir in ${PACKAGES_SEARCH_ROOT_ABSOLUTE_DIRS}; do
		local package_dirpath="${package_src_dir}/${package_name}"
		if [ -d "${package_dirpath}" ]; then
			display_alert "Adding found files" "${package_dirpath} for '${package_name}'" "debug"
			run_host_command_logged cp -r "${package_dirpath}/"* "${destination}/"
		else
			display_alert "No files found in" "${package_dirpath} for '${package_name}'" "debug"
		fi
	done
}
