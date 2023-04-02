#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function assert_requires_aggregation() {
	if [[ ${aggregation_has_already_run:-0} -lt 1 ]]; then
		exit_with_error "assert_requires_aggregation: Aggregation has not been run. This is a bug in armbian-next code. Please report!"
	fi
}

function mark_aggregation_required_in_default_build_start() {
	declare -i -g -r aggregation_required_in_default_build_start=1 # global, readonly.
}

function aggregate_packages_in_logging_section() {
	# Aggregate packages, in its own logging section
	# We need aggregation to be able to build bsp packages, which contain scripts coming from the aggregation.
	LOG_SECTION="aggregate_packages" do_with_logging aggregate_packages
}

# This used to be called from config (main-config), but now it's moved default-build, after prepare_host, so Python hostdeps are available.
# So the aggregation results (hash, etc) are not available for config-dump.
function aggregate_packages() {

	if [[ ${aggregation_has_already_run:-0} -gt 0 ]]; then
		exit_with_error "aggregate_packages: Aggregation has already run"
	fi

	display_alert "Aggregating packages" "rootfs" "info"
	aggregate_all_packages_python
	call_extension_method "post_aggregate_packages" "user_config_post_aggregate_packages" <<- 'POST_AGGREGATE_PACKAGES'
		*After all aggregations are done*
		Called after aggregating all package lists.
		Packages will still be installed after this is called. It is not possible to change anything, though.
	POST_AGGREGATE_PACKAGES

	declare -i -g -r aggregation_has_already_run=1 # global, readonly.

}

function aggregate_all_packages_python() {
	prepare_python_and_pip

	# Get a temporary file for the output. This is not WORKDIR yet, since we're still in configuration phase.
	temp_file_for_aggregation="$(mktemp)"

	# array with all parameters; will be auto-quoted by bash's @Q modifier below
	declare -a aggregation_params_quoted=(
		"${PYTHON3_VARS[@]}"      # Default vars, from prepare_python_and_pip
		"LOG_DEBUG=${SHOW_DEBUG}" # Logging level for python.
		"SRC=${SRC}"
		"OUTPUT=${temp_file_for_aggregation}"
		"ASSET_LOG_BASE=$(print_current_asset_log_base_file)" # base file name for the asset log; to write .md summaries.

		# For the main packages, and others; main packages are not mixed with BOARD or DESKTOP packages.
		# Results:
		# - AGGREGATED_DEBOOTSTRAP_COMPONENTS
		# - AGGREGATED_PACKAGES_DEBOOTSTRAP
		# - AGGREGATED_PACKAGES_ROOTFS
		# - AGGREGATED_PACKAGES_IMAGE

		"ARCH=${ARCH}"
		"RELEASE=${RELEASE}"
		"LINUXFAMILY=" # empty. Important: LINUXFAMILY is no longer considered for package aggregation.
		"BOARD="       # empty. Important: BOARD is no longer considered for package aggregation
		"USERPATCHES_PATH=${USERPATCHES_PATH}"
		"SELECTED_CONFIGURATION=${SELECTED_CONFIGURATION}"
		"BUILD_MINIMAL=${BUILD_MINIMAL}" # if yes, it does not include packages.additional, on top of differences of SELECTED_CONFIGURATION

		# Removals. Will remove from all lists.
		"REMOVE_PACKAGES=${REMOVE_PACKAGES[*]}"
		"REMOVE_PACKAGES_REFS=${REMOVE_PACKAGES_REFS[*]}"

		# Extra packages in rootfs (cached)
		"EXTRA_PACKAGES_ROOTFS=${EXTRA_PACKAGES_ROOTFS[*]}"
		"EXTRA_PACKAGES_ROOTFS_REFS=${EXTRA_PACKAGES_ROOTFS_REFS[*]}"

		# Extra packages, in image (not cached)
		"EXTRA_PACKAGES_IMAGE=${EXTRA_PACKAGES_IMAGE[*]}"
		"EXTRA_PACKAGES_IMAGE_REFS=${EXTRA_PACKAGES_IMAGE_REFS[*]}"

		# Desktop stuff; results are not mixed into main packages. Results in AGGREGATED_PACKAGES_DESKTOP.
		"BUILD_DESKTOP=${BUILD_DESKTOP}"
		"DESKTOP_ENVIRONMENT=${DESKTOP_ENVIRONMENT}"
		"DESKTOP_ENVIRONMENT_CONFIG_NAME=${DESKTOP_ENVIRONMENT_CONFIG_NAME}"
		"DESKTOP_APPGROUPS_SELECTED=${DESKTOP_APPGROUPS_SELECTED}"

		# Those are processed by Python, but not part of rootfs / main packages; results in AGGREGATED_PACKAGES_IMAGE_INSTALL
		# These two vars are made readonly after sourcing the board / family config, so can't be used in extensions and such.
		"PACKAGE_LIST_FAMILY=${PACKAGE_LIST_FAMILY}"
		"PACKAGE_LIST_BOARD=${PACKAGE_LIST_BOARD}"

		# Those are processed by Python, but not part of rootfs / main packages; results in AGGREGATED_PACKAGES_IMAGE_UNINSTALL
		# These two vars are made readonly after sourcing the board / family config, so can't be used in extensions and such.
		"PACKAGE_LIST_BOARD_REMOVE=${PACKAGE_LIST_BOARD_REMOVE}"
		"PACKAGE_LIST_FAMILY_REMOVE=${PACKAGE_LIST_FAMILY_REMOVE}"
	)

	# "raw_command" is only for logging purposes.
	raw_command="[...shortened...] ${PYTHON3_INFO[BIN]} ${SRC}/lib/tools/aggregation.py" \
		run_host_command_logged env -i "${aggregation_params_quoted[@]@Q}" "${PYTHON3_INFO[BIN]}" "${SRC}/lib/tools/aggregation.py"

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		display_alert "Showing aggregation results" "below" "debug"
		run_tool_batcat --file-name "aggregation_results/aggregation_results.sh" "${temp_file_for_aggregation}"
	fi

	# shellcheck disable=SC1090
	source "${temp_file_for_aggregation}" # SOURCE IT!
	run_host_command_logged rm -f "${temp_file_for_aggregation}"
}
