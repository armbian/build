#!/usr/bin/env bash

function aggregate_all_packages() {
	# Get a temporary file for the output. This is not WORKDIR yet, since we're still in configuration phase.
	temp_file_for_aggregation="$(mktemp)"

	# array with all parameters; will be auto-quoted by bash's @Q modifier below
	declare -a aggregation_params_quoted=(
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
		"LINUXFAMILY=${LINUXFAMILY}"
		"BOARD=${BOARD}"
		"USERPATCHES_PATH=${USERPATCHES_PATH}"
		"SELECTED_CONFIGURATION=${SELECTED_CONFIGURATION}"

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
	run_host_command_logged env -i "${aggregation_params_quoted[@]@Q}" python3 "${SRC}/lib/tools/aggregation.py"
	#run_host_command_logged cat "${temp_file_for_aggregation}"
	# shellcheck disable=SC1090
	source "${temp_file_for_aggregation}" # SOURCE IT!
	run_host_command_logged rm "${temp_file_for_aggregation}"
}
