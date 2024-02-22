#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function prepare_ansi_git_info_log_header() {
	# writes to stdout, ANSI format

	declare prefix_sed_cmd="/^-->/!s/^/   /;" # some spacing in front of git info
	cat <<- GIT_ANSI_HEADER
		$(echo -e -n "${bright_blue_color:-}")# GIT revision$(echo -e -n "${ansi_reset_color:-}")
		$(LC_ALL=C LANG=C git --git-dir="${SRC}/.git" log -1 --color --format=short --decorate | sed -e "${prefix_sed_cmd}" || true)
		${dim_line_separator}
		$(echo -e -n "${bright_blue_color:-}")# GIT status$(echo -e -n "${ansi_reset_color:-}")
		$(LC_ALL=C LANG=C git -c color.status=always --work-tree="${SRC}" --git-dir="${SRC}/.git" status | sed -e "${prefix_sed_cmd}" || true)
		${dim_line_separator}
	GIT_ANSI_HEADER
}

# This only includes a header, and all the .md logfiles, nothing else.
function export_markdown_logs() {
	# check target_file variable is not empty
	if [[ -z "${target_file}" ]]; then
		display_alert "No target file specified for export_markdown_logs()" "${target_file}" "err"
		return 0
	fi

	local ascii_log_file="${1:-}"
	display_alert "Preparing Markdown log from" "${LOGDIR} (${ascii_log_file})" "debug"

	cat <<- MARKDOWN_HEADER > "${target_file}"
		<details><summary>Build: ${ARMBIAN_ORIGINAL_ARGV[*]}</summary>
		<p>

		### Armbian logs for ${ARMBIAN_BUILD_UUID}
		#### Armbian build at $(LC_ALL=C LANG=C date) on $(hostname || true)
		#### Repeat build: ${repeat_args_string:-""}
		#### ARGs: \`${ARMBIAN_ORIGINAL_ARGV[@]@Q}\`
	MARKDOWN_HEADER

	if [[ -n "$(command -v git)" && -d "${SRC}/.git" ]]; then
		# If in GHA, very unlikely there will be changes, don't waste space.
		if [[ "${CI}" == "true" ]] && [[ "${GITHUB_ACTIONS}" == "true" ]]; then
			display_alert "Gathering git info for logs" "Processing git information, GHA version" "debug"
			cat <<- GIT_MARKDOWN_HEADER_GHA >> "${target_file}"
				#### Current revision:
				\`\`\`
				$(LC_ALL=C LANG=C git --git-dir="${SRC}/.git" log -1 --format=short --decorate)
				\`\`\`
			GIT_MARKDOWN_HEADER_GHA
		else
			display_alert "Gathering git info for logs" "Processing git information, please wait..." "debug"
			cat <<- GIT_MARKDOWN_HEADER >> "${target_file}"
				#### Current revision:
				\`\`\`
				$(LC_ALL=C LANG=C git --git-dir="${SRC}/.git" log -1 --format=short --decorate)
				\`\`\`
				#### Git status:
				\`\`\`
				$(LC_ALL=C LANG=C git --work-tree="${SRC}" --git-dir="${SRC}/.git" status)
				\`\`\`
				#### Git changes:
				\`\`\`
				$(LC_ALL=C LANG=C git --work-tree="${SRC}" --git-dir="${SRC}/.git" diff -u)
				\`\`\`
			GIT_MARKDOWN_HEADER
		fi
	fi

	# FOOTER: Newlines are relevant here.
	echo -e "\n\n</p></details>\n\n" >> "${target_file}"

	display_alert "Preparing Markdown logs..." "Processing log files..." "debug"

	# Find and sort the files there, store in array one per logfile
	declare -a logfiles_array
	mapfile -t logfiles_array < <(find "${LOGDIR}" -type f | grep "\.md\$" | LC_ALL=C sort -h) # "human" sorting
	for logfile_full in "${logfiles_array[@]}"; do
		cat "${logfile_full}" >> "${target_file}"
	done

	# If running in GHA, include the ascii logs as well, side a collapsible section.
	if [[ "${CI}" == "true" ]] && [[ "${GITHUB_ACTIONS}" == "true" ]]; then
		if [[ -f "${ascii_log_file}" ]]; then
			# Newlines are relevant here.
			cat <<- MARKDOWN_LOG_HEADER >> "${target_file}"
				<details><summary>ASCII logs: ${ARMBIAN_BUILD_UUID}</summary>
				<p>

				\`\`\`bash
			MARKDOWN_LOG_HEADER

			# GHA has a 1mb limit for Markdown. 500kb of logs, max, from the end.
			tail --bytes 500000 "${ascii_log_file}" >> "${target_file}" || true
			echo -e "\n\`\`\`\n\n</p></details>\n\n" >> "${target_file}"
		fi
	fi

	return 0
}

# Export logs in plain format.
function export_ansi_logs() {
	# check target_file variable is not empty
	if [[ -z "${target_file}" ]]; then
		display_alert "No target file specified for export_markdown_logs()" "${target_file}" "err"
		return 0
	fi

	display_alert "Preparing ANSI log from" "${LOGDIR}" "debug"

	declare dim_line_separator
	dim_line_separator=$(echo -e -n "${gray_color:-}")------------------------------------------------------------------------------------------------------------$(echo -e -n "${ansi_reset_color:-}")

	cat <<- ANSI_HEADER > "${target_file}"
		# Armbian ANSI build logs for ${ARMBIAN_BUILD_UUID} - use "less -SR" to view
		$(echo -e -n "${bright_blue_color:-}")# Armbian build at $(LC_ALL=C LANG=C date) on $(hostname || true)$(echo -e -n "${ansi_reset_color}")
		${dim_line_separator}
		$(echo -e -n "${bright_blue_color}")# Repeat build: ${repeat_args_string:-""}$(echo -e -n "${ansi_reset_color}")
		$(echo -e -n "${bright_blue_color}")# ARGs: ${ARMBIAN_ORIGINAL_ARGV[@]@Q}$(echo -e -n "${ansi_reset_color}")
		${dim_line_separator}
	ANSI_HEADER

	if [[ -n "${GIT_INFO_ANSI}" ]]; then
		echo "${GIT_INFO_ANSI}" >> "${target_file}"
	elif [[ -n "$(command -v git)" && -d "${SRC}/.git" ]]; then # we don't have .git inside Docker...
		display_alert "Gathering git info for logs" "Processing git information, please wait..." "debug"
		prepare_ansi_git_info_log_header >> "${target_file}"
	else
		display_alert "Gathering git info for logs" "No git information available" "debug"
	fi

	display_alert "Preparing ANSI logs..." "Processing log files..." "debug"

	# Find and sort the files there, store in array one per logfile
	declare -a logfiles_array
	mapfile -t logfiles_array < <(find "${LOGDIR}" -type f | LC_ALL=C sort -h) # "human" sorting

	declare prefix_sed_contents
	prefix_sed_contents="   $(echo -n -e "${ansi_reset_color}${tool_color:-}")" # spaces are significant
	declare prefix_sed_cmd="/^-->/!s/^/${prefix_sed_contents}/;"

	declare logfile_full
	for logfile_full in "${logfiles_array[@]}"; do
		[[ ! -s "${logfile_full}" ]] && continue # skip empty files
		declare logfile_base logfile_title
		logfile_base="$(basename "${logfile_full}")"
		[[ ! "${logfile_base}" =~ \.log$ ]] && continue # only .log files; others should be in Markdown logs

		# remove everything before the second dot to produce the title
		# shellcheck disable=SC2001 # I saw, and I can't
		logfile_title="$(echo "${logfile_base}" | sed -e 's/^[^.]*\.[^.]*\.//')"

		# shellcheck disable=SC2002 # cats, not useless, I like.
		cat <<- ANSI_ONE_LOGFILE >> "${target_file}"
			$(echo -e -n "${bright_blue_color}")### ${logfile_title} $(echo -e -n "${ansi_reset_color}")
			$(cat "${logfile_full}" | sed -e "${prefix_sed_cmd}")
			${dim_line_separator}
		ANSI_ONE_LOGFILE
	done

	declare target_relative_to_src
	target_relative_to_src="$(realpath --relative-to="${SRC}" "${target_file}")"

	if [[ "${show_message_after_export:-"yes"}" != "skip" && "${ARMBIAN_INSIDE_DOCKERFILE_BUILD:-"no"}" != "yes" ]]; then
		display_alert "ANSI log file built; inspect it by running:" "less -RS ${target_relative_to_src}"

		# @TODO: compress...
		declare paste_url="${PASTE_URL:-"https://paste.next.armbian.com/log"}"
		if [[ "${SHARE_LOG:-"no"}" == "yes" ]]; then
			display_alert "SHARE_LOG=yes, uploading log" "uploading logs" "info"
			declare logs_url="undetermined"
			logs_url=$(curl --silent --data-binary "@${target_relative_to_src}" "${paste_url}" | xargs echo -n || true) # don't fail
			display_alert "Log uploaded, share URL:" "${logs_url}" ""
			# set output for GitHub Actions
			github_actions_add_output logs_url "${logs_url}"
		else
			display_alert "Share log manually (or SHARE_LOG=yes):" "curl --data-binary @${target_relative_to_src} ${paste_url}"
		fi
	fi

	return 0
}

function export_raw_logs() {
	display_alert "Exporting RAW logs from" "${LOGDIR}" "info"
	if [[ -z "${target_file}" ]]; then
		display_alert "No target file specified for export_raw_logs()" "${target_file}" "err"
		return 0
	fi

	# Just tar the logs directory into target_file
	tar -C "${LOGDIR}" -cf "${target_file}" .
}
