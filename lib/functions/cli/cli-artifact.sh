#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function cli_artifact_pre_run() {
	case "${ARMBIAN_COMMAND}" in
		download-artifact)
			display_alert "download-only mode:" "won't build '${WHAT}'" "info"
			declare -g DONT_BUILD_ARTIFACTS="${WHAT}"
			declare -g KEEP_HASHED_DEB_ARTIFACTS="yes"
			;;
	esac

	initialize_artifact "${WHAT}"
	# Run the pre run adapter
	artifact_cli_adapter_pre_run
}

function cli_artifact_run() {
	: "${chosen_artifact:?chosen_artifact is not set}"
	: "${chosen_artifact_impl:?chosen_artifact_impl is not set}"

	if [[ "${CONFIG_DEFS_ONLY}" != "yes" ]]; then
		# Make sure ORAS tooling is installed before starting.
		run_tool_oras
	fi

	display_alert "artifact" "${chosen_artifact}" "debug"
	display_alert "artifact" "${chosen_artifact} :: ${chosen_artifact_impl}()" "debug"
	declare -g artifact_version_requires_aggregation="no" # marker
	artifact_cli_adapter_config_prep                      # only if in cli.

	# if asked by _config_prep to aggregate, and HOSTRELEASE is not set, obtain it.
	if [[ "${artifact_version_requires_aggregation}" == "yes" ]] && [[ -z "${HOSTRELEASE}" ]]; then
		obtain_hostrelease_only # Sets HOSTRELEASE
	fi

	declare deploy_to_remote="no"

	case "${ARMBIAN_COMMAND}" in
		download-artifact)
			display_alert "Running in download-artifact mode" "download-artifact" "ext"
			;;
		*)
			# Warn of deprecation...
			if [[ "${ARTIFACT_USE_CACHE}" == "yes" ]]; then
				display_alert "deprecated!" "ARTIFACT_USE_CACHE=yes is deprecated, its behaviour is now the default." "warn"
			fi

			# If UPLOAD_TO_OCI_ONLY=yes is explicitly set; deploy to remote.
			if [[ "${UPLOAD_TO_OCI_ONLY}" == "yes" ]]; then
				display_alert "UPLOAD_TO_OCI_ONLY=yes is set" "UPLOAD_TO_OCI_ONLY=yes; ignoring local cache and deploying to remote" "info"
				deploy_to_remote="yes"
			fi
			;;
	esac

	if [[ "${ARTIFACT_BUILD_INTERACTIVE}" == "yes" ]]; then # Set by `kernel-config`, `kernel-patch`, `uboot-config`, `uboot-patch`, etc.
		display_alert "Running artifact build in interactive mode" "log file will be incomplete" "info"
		do_with_default_build obtain_complete_artifact
	else
		do_with_default_build obtain_complete_artifact < /dev/null
	fi
}
