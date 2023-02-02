function run_tool_shellcheck() {
	# Default version
	SHELLCHECK_VERSION=${SHELLCHECK_VERSION:-0.9.0} # https://github.com/koalaman/shellcheck/releases

	declare non_cache_dir="/armbian-tools/shellcheck" # To deploy/reuse cached SHELLCHECK in a Docker image.

	if [[ -z "${DIR_SHELLCHECK}" ]]; then
		display_alert "DIR_SHELLCHECK is not set, using default" "SHELLCHECK" "debug"

		if [[ "${deploy_to_non_cache_dir:-"no"}" == "yes" ]]; then
			DIR_SHELLCHECK="${non_cache_dir}" # root directory.
			display_alert "Deploying SHELLCHECK to non-cache dir" "DIR_SHELLCHECK: ${DIR_SHELLCHECK}" "debug"
		else
			if [[ -n "${SRC}" ]]; then
				DIR_SHELLCHECK="${SRC}/cache/tools/shellcheck"
			else
				display_alert "Missing DIR_SHELLCHECK, or SRC fallback" "DIR_SHELLCHECK: ${DIR_SHELLCHECK}; SRC: ${SRC}" "SHELLCHECK" "err"
				return 1
			fi
		fi
	else
		display_alert "DIR_SHELLCHECK is set to ${DIR_SHELLCHECK}" "SHELLCHECK" "debug"
	fi

	mkdir -p "${DIR_SHELLCHECK}"

	declare MACHINE="${BASH_VERSINFO[5]}" SHELLCHECK_OS SHELLCHECK_ARCH
	display_alert "Running SHELLCHECK" "SHELLCHECK version ${SHELLCHECK_VERSION}" "debug"
	MACHINE="${BASH_VERSINFO[5]}"
	case "$MACHINE" in
		*darwin*) SHELLCHECK_OS="darwin" ;;
		*linux*) SHELLCHECK_OS="linux" ;;
		*)
			exit_with_error "unknown os: $MACHINE"
			;;
	esac

	case "$MACHINE" in
		*aarch64*) SHELLCHECK_ARCH="aarch64" ;;
		*x86_64*) SHELLCHECK_ARCH="x86_64" ;;
		*)
			exit_with_error "unknown arch: $MACHINE"
			;;
	esac

	# Check if we have a cached version in a Docker image, and copy it over before possibly updating it.
	if [[ "${deploy_to_non_cache_dir:-"no"}" != "yes" && -d "${non_cache_dir}" ]]; then
		display_alert "Using cached SHELLCHECK from Docker image" "SHELLCHECK" "debug"
		run_host_command_logged cp -v "${non_cache_dir}/"* "${DIR_SHELLCHECK}/"
	fi

	declare SHELLCHECK_FN="shellcheck-v${SHELLCHECK_VERSION}.${SHELLCHECK_OS}.${SHELLCHECK_ARCH}"
	declare SHELLCHECK_FN_TARXZ="${SHELLCHECK_FN}.tar.xz"
	declare DOWN_URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${SHELLCHECK_FN_TARXZ}"
	declare SHELLCHECK_BIN="${DIR_SHELLCHECK}/${SHELLCHECK_FN}"
	declare ACTUAL_VERSION

	if [[ ! -f "${SHELLCHECK_BIN}" ]]; then
		do_with_retries 5 try_download_shellcheck_tooling
	fi
	ACTUAL_VERSION="$("${SHELLCHECK_BIN}" --version | grep "^version" | xargs echo -n)"
	display_alert "Running SHELLCHECK ${ACTUAL_VERSION}" "SHELLCHECK" "debug"

	if [[ "${deploy_to_non_cache_dir:-"no"}" == "yes" ]]; then
		display_alert "Deployed SHELLCHECK to non-cache dir" "DIR_SHELLCHECK: ${DIR_SHELLCHECK}" "debug"
		return 0 # don't actually execute.
	fi

	# Run shellcheck with it
	display_alert "Calling SHELLCHECK" "$*" "debug"
	"${SHELLCHECK_BIN}" "$@"
}

function try_download_shellcheck_tooling() {
	display_alert "MACHINE: ${MACHINE}" "SHELLCHECK" "debug"
	display_alert "Down URL: ${DOWN_URL}" "SHELLCHECK" "debug"
	display_alert "SHELLCHECK_BIN: ${SHELLCHECK_BIN}" "SHELLCHECK" "debug"

	display_alert "Downloading required" "SHELLCHECK tooling${RETRY_FMT_MORE_THAN_ONCE}" "info"
	run_host_command_logged wget --no-verbose --progress=dot:giga -O "${SHELLCHECK_BIN}.tar.xz.tmp" "${DOWN_URL}" || {
		return 1
	}

	run_host_command_logged mv "${SHELLCHECK_BIN}.tar.xz.tmp" "${SHELLCHECK_BIN}.tar.xz"
	run_host_command_logged tar -xf "${SHELLCHECK_BIN}.tar.xz" -C "${DIR_SHELLCHECK}" "shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
	run_host_command_logged mv "${DIR_SHELLCHECK}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "${SHELLCHECK_BIN}"
	run_host_command_logged rm -rf "${DIR_SHELLCHECK}/shellcheck-v${SHELLCHECK_VERSION}" "${SHELLCHECK_BIN}.tar.xz"
	run_host_command_logged chmod +x "${SHELLCHECK_BIN}"
}
