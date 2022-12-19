function run_tool_oras() {
	# Default version
	ORAS_VERSION=${ORAS_VERSION:-0.16.0} # https://github.com/oras-project/oras/releases

	if [[ -z "${DIR_ORAS}" ]]; then
		display_alert "DIR_ORAS is not set, using default" "ORAS" "debug"
		if [[ -n "${SRC}" ]]; then
			DIR_ORAS="${SRC}/cache/tools/oras"
		else
			display_alert "Missing DIR_ORAS, or SRC fallback" "DIR_ORAS: ${DIR_ORAS}; SRC: ${SRC}" "ORAS" "err"
			return 1
		fi
	else
		display_alert "DIR_ORAS is set to ${DIR_ORAS}" "ORAS" "debug"
	fi

	mkdir -p "${DIR_ORAS}"

	declare MACHINE="${BASH_VERSINFO[5]}" ORAS_OS ORAS_ARCH
	display_alert "Running ORAS" "ORAS version ${ORAS_VERSION}" "debug"
	MACHINE="${BASH_VERSINFO[5]}"
	case "$MACHINE" in
		*darwin*) ORAS_OS="darwin" ;;
		*linux*) ORAS_OS="linux" ;;
		*)
			exit_with_error "unknown os: $MACHINE"
			;;
	esac

	case "$MACHINE" in
		*aarch64*) ORAS_ARCH="arm64" ;;
		*x86_64*) ORAS_ARCH="amd64" ;;
		*)
			exit_with_error "unknown arch: $MACHINE"
			;;
	esac

	declare ORAS_FN="oras_${ORAS_VERSION}_${ORAS_OS}_${ORAS_ARCH}"
	declare ORAS_FN_TARXZ="${ORAS_FN}.tar.gz"
	declare DOWN_URL="https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/${ORAS_FN_TARXZ}"
	declare ORAS_BIN="${DIR_ORAS}/${ORAS_FN}"
	declare ACTUAL_VERSION

	if [[ ! -f "${ORAS_BIN}" ]]; then
		display_alert "Cache miss, downloading..."
		display_alert "MACHINE: ${MACHINE}" "ORAS" "debug"
		display_alert "Down URL: ${DOWN_URL}" "ORAS" "debug"
		display_alert "ORAS_BIN: ${ORAS_BIN}" "ORAS" "debug"

		display_alert "Downloading required" "ORAS tooling" "info"
		run_host_command_logged wget --progress=dot:giga -O "${ORAS_BIN}.tar.gz" "${DOWN_URL}"
		run_host_command_logged tar -xf "${ORAS_BIN}.tar.gz" -C "${DIR_ORAS}" "oras"
		run_host_command_logged rm -rf "${ORAS_BIN}.tar.gz"
		run_host_command_logged mv -v "${DIR_ORAS}/oras" "${ORAS_BIN}"
		run_host_command_logged chmod -v +x "${ORAS_BIN}"
	fi
	ACTUAL_VERSION="$("${ORAS_BIN}" version | grep "^Version" | xargs echo -n)"
	display_alert "Running ORAS ${ACTUAL_VERSION}" "ORAS" "debug"

	# Run oras with it
	display_alert "Calling ORAS" "$*" "debug"
	"${ORAS_BIN}" "$@"
}

function oras_push_artifact_file() {
	declare image_full_oci="${1}" # Something like "ghcr.io/rpardini/armbian-git-shallow/kernel-git:latest"
	declare upload_file="${2}"    # Absolute path to the file to upload including the path and name
	declare upload_file_base_path upload_file_name
	display_alert "Pushing ${upload_file}" "ORAS to ${image_full_oci}" "info"

	# make sure file exists
	if [[ ! -f "${upload_file}" ]]; then
		display_alert "File not found: ${upload_file}" "ORAS upload" "err"
		return 1
	fi

	# split the path and the filename
	upload_file_base_path="$(dirname "${upload_file}")"
	upload_file_name="$(basename "${upload_file}")"
	display_alert "upload_file_base_path: ${upload_file_base_path}" "ORAS upload" "debug"
	display_alert "upload_file_name: ${upload_file_name}" "ORAS upload" "debug"

	pushd "${upload_file_base_path}" || exit_with_error "Failed to pushd to ${upload_file_base_path} - ORAS upload"
	run_tool_oras push --verbose "${image_full_oci}" "${upload_file_name}:application/vnd.unknown.layer.v1+tar"
	popd || exit_with_error "Failed to popd" "ORAS upload"
	return 0
}

# oras pull is very hard to work with, since we don't determine the filename until after the download.
function oras_pull_artifact_file() {
	declare image_full_oci="${1}" # Something like "ghcr.io/rpardini/armbian-git-shallow/kernel-git:latest"
	declare target_dir="${2}"     # temporary directory we'll use for the download to workaround oras being maniac
	declare target_fn="${3}"

	declare full_temp_dir="${target_dir}/${target_fn}.oras.pull.tmp"
	declare full_tmp_file_path="${full_temp_dir}/${target_fn}"
	run_host_command_logged mkdir -p "${full_temp_dir}"

	pushd "${full_temp_dir}" &> /dev/null || exit_with_error "Failed to pushd to ${full_temp_dir} - ORAS download"
	run_tool_oras pull --verbose "${image_full_oci}"
	popd &> /dev/null || exit_with_error "Failed to popd - ORAS download"

	# sanity check; did we get the file we expected?
	if [[ ! -f "${full_tmp_file_path}" ]]; then
		exit_with_error "File not found after ORAS pull: ${full_tmp_file_path} - ORAS download"
		return 1
	fi

	# move the file to the target directory
	run_host_command_logged mv "${full_tmp_file_path}" "${target_dir}"

	# remove the temp directory
	run_host_command_logged rm -rf "${full_temp_dir}"
}
