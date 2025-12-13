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
	local file source func line message deletion_info
	for deletion_info in "${schedule_deletion_files_to_delete[@]}"; do
		IFS=';' read -r file source func line <<< "$deletion_info"
		message="scheduled from $source $func $line"

		set +e # don't bail out, let us bail out ourselves more verbosely
		if [[ ! -e "$file" ]]; then
			exit_with_error "FILE DELETION FAILED (missing): '${file}'; ${message}"
		elif rm -- "$file"; then
			display_alert "deleted file '${file}'" "$message" "info"
		else
			exit_with_error "FILE DELETION FAILED: '${file}'; ${message}"
		fi
		set -e # restore the previous behaviour
	done
}
