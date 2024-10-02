#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function cli_oras_pre_run() {
	: # Empty, no need to do anything.
}

function cli_oras_run() {
	case "${ORAS_OPERATION}" in
		upload)
			display_alert "Uploading using ORAS" "OCI_TARGET: '${OCI_TARGET}' UPLOAD_FILE='${UPLOAD_FILE}'" "info"
			display_alert "OCI_TARGET" "${OCI_TARGET}" "info"
			display_alert "UPLOAD_FILE" "${UPLOAD_FILE}" "info"
			# if OCI_TARGET is not set, exit_with_error
			if [[ -z "${OCI_TARGET}" ]]; then
				exit_with_error "OCI_TARGET is not set"
			fi
			if [[ -z "${UPLOAD_FILE}" ]]; then
				exit_with_error "UPLOAD_FILE is not set"
			fi
			if [[ ! -f "${UPLOAD_FILE}" ]]; then
				exit_with_error "File to upload not found '${UPLOAD_FILE}'"
			fi
			# This will download & install ORAS and run it.
			oras_push_artifact_file "${OCI_TARGET}" "${UPLOAD_FILE}" "uploaded from command line - this is NOT a Docker image"
			;;

		*)
			exit_with_error "Unknown ORAS_OPERATION '${ORAS_OPERATION}'"
			;;
	esac
	return 0
}
