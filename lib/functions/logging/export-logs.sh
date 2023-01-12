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

	cat <<- ANSI_HEADER > "${target_file}"
		# Armbian logs for ${ARMBIAN_BUILD_UUID}
		# Armbian build at $(LC_ALL=C LANG=C date) on $(hostname || true)
		----------------------------------------------------------------------------------------------------------------
		# ARGs: ${ARMBIAN_ORIGINAL_ARGV[@]@Q}
		----------------------------------------------------------------------------------------------------------------
	ANSI_HEADER

	if [[ -n "$(command -v git)" && -d "${SRC}/.git" ]]; then
		display_alert "Gathering git info for logs" "Processing git information, please wait..." "debug"
		cat <<- GIT_ANSI_HEADER >> "${target_file}"
			----------------------------------------------------------------------------------------------------------------
			# Last revision:
			$(LC_ALL=C LANG=C git --git-dir="${SRC}/.git" log -1 --color --format=short --decorate)
			----------------------------------------------------------------------------------------------------------------
			# Git status:
			$(LC_ALL=C LANG=C git -c color.status=always --work-tree="${SRC}" --git-dir="${SRC}/.git" status)
			----------------------------------------------------------------------------------------------------------------
			# Git changes:
			$(LC_ALL=C LANG=C git --work-tree="${SRC}" --git-dir="${SRC}/.git" diff -u --color)
			----------------------------------------------------------------------------------------------------------------
		GIT_ANSI_HEADER
	fi

	display_alert "Preparing ANSI logs..." "Processing log files..." "debug"

	# Find and sort the files there, store in array one per logfile
	declare -a logfiles_array
	mapfile -t logfiles_array < <(find "${LOGDIR}" -type f | LC_ALL=C sort -h)

	for logfile_full in "${logfiles_array[@]}"; do
		local logfile_base="$(basename "${logfile_full}")"
		cat <<- ANSI_ONE_LOGFILE_NO_CCZE >> "${target_file}"
			------------------------------------------------------------------------------------------------------------
			## ${logfile_base}
			$(cat "${logfile_full}")
			------------------------------------------------------------------------------------------------------------
		ANSI_ONE_LOGFILE_NO_CCZE
	done

	display_alert "Built ANSI log file" "${target_file}"
}

# Export logs in HTML format. (EXPORT_HTML_LOG=yes) -- very slow.
function export_html_logs() {
	display_alert "Preparing HTML log from" "${LOGDIR}" "debug"

	cat <<- ANSI_HEADER > "${target_file}"
		<html>
			<head>
			<title>Armbian logs for ${ARMBIAN_BUILD_UUID}</title>
			<style>
				html, html pre { background-color: black !important; color: white !important; font-family: JetBrains Mono, monospace, cursive !important; }
				hr { border: 0; border-bottom: 1px dashed silver; }
			</style>
			</head>
		<body>
			<h2>Armbian build at $(LC_ALL=C LANG=C date) on $(hostname || true)</h2>
			<h2>${ARMBIAN_ORIGINAL_ARGV[@]@Q}</h2>
			<hr/>

			$(LC_ALL=C LANG=C git --git-dir="${SRC}/.git" log -1 --color --format=short --decorate | ansi2html --no-wrap --no-header)
			<hr/>

			$(LC_ALL=C LANG=C git -c color.status=always --work-tree="${SRC}" --git-dir="${SRC}/.git" status | ansi2html --no-wrap --no-header)
			<hr/>

			$(LC_ALL=C LANG=C git --work-tree="${SRC}" --git-dir="${SRC}/.git" diff -u --color | ansi2html --no-wrap --no-header)
			<hr/>

	ANSI_HEADER

	# Find and sort the files there, store in array one per logfile
	declare -a logfiles_array
	mapfile -t logfiles_array < <(find "${LOGDIR}" -type f | LC_ALL=C sort -h)

	for logfile_full in "${logfiles_array[@]}"; do
		local logfile_base="$(basename "${logfile_full}")"
		if [[ -f /usr/bin/ccze ]] && [[ -f /usr/bin/ansi2html ]]; then
			cat <<- HTML_ONE_LOGFILE_WITH_CCZE >> "${target_file}"
				<h3>${logfile_base}</h3>
				<div style="padding: 1em">
				$(ccze -o nolookups --raw-ansi < "${logfile_full}" | ansi2html --no-wrap --no-header)
				</div>
				<hr/>
			HTML_ONE_LOGFILE_WITH_CCZE
		else
			cat <<- ANSI_ONE_LOGFILE_NO_CCZE >> "${target_file}"
				<h3>${logfile_base}</h3>
				<pre>$(cat "${logfile_full}")</pre>
			ANSI_ONE_LOGFILE_NO_CCZE
		fi
	done

	cat <<- HTML_FOOTER >> "${target_file}"
		</body></html>
	HTML_FOOTER

	display_alert "Built HTML log file" "${target_file}"
}
