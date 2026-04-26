#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function compile_stubble() {
	if [[ "${KERNEL_DO_STUBBLE}" != "yes" ]]; then
		return 0
	fi

	display_alert "Preparing stubble" "EFI stub with device-tree loading capability" "info"

	# Stubble source configuration
	declare STUBBLE_GIT_URL="${STUBBLE_GIT_URL:-"https://github.com/ubuntu/stubble.git"}"
	declare STUBBLE_GIT_BRANCH="${STUBBLE_GIT_BRANCH:-"branch:main"}"
	declare STUBBLE_GIT_DIR="stubble"

	# Fetch stubble source
	display_alert "Downloading stubble sources" "stubble" "git"
	fetch_from_repo "${STUBBLE_GIT_URL}" "${STUBBLE_GIT_DIR}" "${STUBBLE_GIT_BRANCH}" "yes"

	# When ref_subdir="yes", fetch_from_repo puts sources in subdirectory named after branch
	declare stubble_branch_name="${STUBBLE_GIT_BRANCH#branch:}"
	declare stubble_source_dir="${SRC}/cache/sources/${STUBBLE_GIT_DIR}/${stubble_branch_name}"

	# Use overlayfs if enabled
	if [[ "${USE_OVERLAYFS}" == "yes" ]]; then
		stubble_source_dir=$(overlayfs_wrapper "wrap" "${stubble_source_dir}" "stubble_${LINUXFAMILY}_${BRANCH}")
	fi

	cd "${stubble_source_dir}" || exit_with_error "Failed to change to stubble source directory" "${stubble_source_dir}"

	display_alert "Stubble source directory" "${stubble_source_dir}" "debug"

	# Determine target architecture for stubble build
	declare STUBBLE_ARCH
	declare STUB_GNU_TYPE
	case "${ARCH}" in
		amd64)
			STUBBLE_ARCH="x86_64"
			STUB_GNU_TYPE="x86_64-linux-gnu"
			;;
		arm64)
			STUBBLE_ARCH="aarch64"
			STUB_GNU_TYPE="aarch64-linux-gnu"
			;;
		riscv64)
			STUBBLE_ARCH="riscv64"
			STUB_GNU_TYPE="riscv64-linux-gnu"
			;;
		*)
			exit_with_error "Unsupported architecture for stubble" "${ARCH}"
			;;
	esac

	display_alert "Building stubble for architecture" "${STUBBLE_ARCH}" "info"

	# Always clean before build to ensure no stale object files
	run_host_command_logged make clean

	# Build using the standard Makefile with cross-compilation
	run_host_command_logged make \
		ARCH="${STUBBLE_ARCH}" \
		CC="${STUB_GNU_TYPE}-gcc"

	declare stubble_efi_path="${stubble_source_dir}/stubble.efi"

	# Verify the build output
	if [[ ! -f "${stubble_efi_path}" ]]; then
		display_alert "stubble.efi not found at expected path, searching..." "" "wrn"
		stubble_efi_path=$(find "${stubble_source_dir}" -name "stubble.efi" -type f | head -1)
		if [[ -z "${stubble_efi_path}" ]]; then
			exit_with_error "stubble build failed - stubble.efi not found"
		fi
	fi

	display_alert "stubble.efi built successfully" "${stubble_efi_path}" "info"
	run_host_command_logged file "${stubble_efi_path}"

	# Export paths for kernel packaging - use paths from stubble source
	declare -g STUBBLE_EFI_PATH="${stubble_efi_path}"
	declare -g STUBBLE_FIND_DTBS="${stubble_source_dir}/hwids/finddtbs.py"
	declare -g STUBBLE_HWIDS_DIR="${stubble_source_dir}/hwids/json"

	# Generate sbat file from template (similar to debian/rules)
	declare sbat_template="${stubble_source_dir}/debian/sbat.in"
	declare sbat_output="${stubble_source_dir}/sbat"
	if [[ -f "${sbat_template}" ]]; then
		sed -e "s,@DEBIAN_VERSION@,9-1," \
		    -e "s,@UPSTREAM_VERSION@,9," \
		    "${sbat_template}" > "${sbat_output}"
		display_alert "Generated sbat file from template" "${sbat_output}" "debug"
	else
		# Create sbat file manually if template doesn't exist
		cat > "${sbat_output}" <<- SBAT
			sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md
			stubble,1,Canonical,stubble,9,https://github.com/ubuntu/stubble
			stubble.ubuntu,1,Canonical,stubble,9-1,https://launchpad.net/ubuntu/+source/stubble
		SBAT
		display_alert "Created sbat file manually" "${sbat_output}" "debug"
	fi

	# Validate sbat file
	if [[ ! -s "${sbat_output}" ]]; then
		exit_with_error "Generated sbat file is empty or missing" "${sbat_output}"
	fi

	declare -g STUBBLE_SBAT_PATH="${sbat_output}"

	return 0
}
