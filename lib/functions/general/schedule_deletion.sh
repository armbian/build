# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2025 tabris <tabris@tabris.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/

declare -a schedule_deletion_files_to_delete

function schedule_deletion() {
	local file="$1"
	local source="${BASH_SOURCE[1]}"
	local func="${FUNCNAME[1]}"
	local line="${BASH_LINENO[0]}"

	schedule_deletion_files_to_delete+=("$file;$source;$func;$line")
}

function pre_umount_final_image__schedule_deletion_delete_now() {
	local file source func line deletion_info
	local had_errexit=0
	case $- in *e*) had_errexit=1;; esac
	for deletion_info in "${schedule_deletion_files_to_delete[@]}"; do
		IFS=';' read -r file source func line <<< "$deletion_info"
		local reason="scheduled from $source $func line#$line"
		local message=""
		local failure=0

		[[ $had_errexit ]] && set +e # don't bail out, let us bail out ourselves more verbosely
		if [[ ! -e "$file" ]]; then
			message="FILE DELETION FAILED (missing): '${file}'"
			((failure++))
		elif rm -- "$file"; then
			message="deleted file '${file}'"
		else
			message="FILE DELETION FAILED: '${file}'"
			((failure++))
		fi
		[[ $had_errexit ]] && set -e # restore the previous behaviour
		if [[ $failure ]]; then
			exit_with_error "$message; $reason"
		else
			display_alert "$message" "$reason" "info"
		fi
	done
}
