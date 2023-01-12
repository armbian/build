# This only includes a header, and all the .md logfiles, nothing else.
function export_markdown_logs() {
	display_alert "Preparing Markdown log from" "${LOGDIR}" "debug"

	cat <<- MARKDOWN_HEADER > "${target_file}"
		<details><summary>Build: ${ARMBIAN_ORIGINAL_ARGV[*]}</summary>
		<p>

		### Armbian logs for ${ARMBIAN_BUILD_UUID}
		#### Armbian build at $(LC_ALL=C LANG=C date) on $(hostname || true)
		#### ARGs: \`${ARMBIAN_ORIGINAL_ARGV[@]@Q}\`
	MARKDOWN_HEADER

	if [[ -n "$(command -v git)" && -d "${SRC}/.git" ]]; then
		display_alert "Gathering git info for logs" "Processing git information, please wait..." "debug"
		cat <<- GIT_MARKDOWN_HEADER >> "${target_file}"
			#### Last revision:
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

	# Newlines are relevant here.
	echo -e "\n\n</p></details>\n\n" >> "${target_file}"

	display_alert "Preparing Markdown logs..." "Processing log files..." "debug"

	# Find and sort the files there, store in array one per logfile
	declare -a logfiles_array
	mapfile -t logfiles_array < <(find "${LOGDIR}" -type f | grep "\.md\$" | LC_ALL=C sort -h)
	for logfile_full in "${logfiles_array[@]}"; do
		cat "${logfile_full}" >> "${target_file}"
	done

	return 0
}

# Export logs in plain format.
function export_ansi_logs() {
	display_alert "Preparing ANSI log from" "${LOGDIR}" "debug"

	declare dim_line_separator
	dim_line_separator=$(echo -e -n "${gray_color:-}")------------------------------------------------------------------------------------------------------------$(echo -e -n "${normal_color:-}")

	cat <<- ANSI_HEADER > "${target_file}"
		# Armbian logs for ${ARMBIAN_BUILD_UUID}
		# Armbian build at $(LC_ALL=C LANG=C date) on $(hostname || true)
		${dim_line_separator}
		# ARGs: ${ARMBIAN_ORIGINAL_ARGV[@]@Q}
		${dim_line_separator}
	ANSI_HEADER

	if [[ -n "$(command -v git)" && -d "${SRC}/.git" ]]; then
		display_alert "Gathering git info for logs" "Processing git information, please wait..." "debug"
		cat <<- GIT_ANSI_HEADER >> "${target_file}"
			# Last revision:
			$(LC_ALL=C LANG=C git --git-dir="${SRC}/.git" log -1 --color --format=short --decorate || true)
			${dim_line_separator}
			# Git status:
			$(LC_ALL=C LANG=C git -c color.status=always --work-tree="${SRC}" --git-dir="${SRC}/.git" status || true)
			${dim_line_separator}
			# Git changes:
			$(LC_ALL=C LANG=C git --work-tree="${SRC}" --git-dir="${SRC}/.git" diff -u --color || true)
			${dim_line_separator}
		GIT_ANSI_HEADER
	fi

	display_alert "Preparing ANSI logs..." "Processing log files..." "debug"

	# Find and sort the files there, store in array one per logfile
	declare -a logfiles_array
	mapfile -t logfiles_array < <(find "${LOGDIR}" -type f | LC_ALL=C sort -h) # "human" sorting

	prefix_sed_contents="   $(echo -n -e "${tool_color:-}")" # spaces are significant
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

		cat <<- ANSI_ONE_LOGFILE >> "${target_file}"
			$(echo -e -n "\033[94m")### ${logfile_title} $(echo -e -n "${normal_color}")
			$(cat "${logfile_full}" | sed -e "${prefix_sed_cmd}")
			${dim_line_separator}
		ANSI_ONE_LOGFILE
	done

	declare target_relative_to_src
	target_relative_to_src="$(realpath --relative-to="${SRC}" "${target_file}")"

	display_alert "ANSI log file built; inspect it by running:" "less -RS ${target_relative_to_src}"
}
