function calculate_hash_for_files() {
	declare -a hashes=()
	for file in "$@"; do
		hash="$(sha256sum "${file}" | cut -d' ' -f1)"
		hashes+=("$hash")
	done
	hash_files="$(echo "${hashes[@]}" | sha256sum | cut -d' ' -f1)" # now, hash the hashes
	hash_files="${hash_files:0:16}"                                 # shorten it to 16 characters
	display_alert "Hash for files:" "$hash_files" "debug"
}

function kernel_drivers_create_patches() {
	declare kernel_work_dir="${1}"
	declare kernel_git_revision="${2}"

	declare hash_files # any changes in these two files will trigger a cache miss.
	calculate_hash_for_files "${SRC}/lib/functions/compilation/patch/drivers_network.sh" "${SRC}/lib/functions/compilation/patch/drivers-harness.sh"

	declare cache_key_base="${KERNEL_MAJOR_MINOR}_${LINUXFAMILY}"
	declare cache_key="${cache_key_base}_${hash_files}"
	display_alert "Cache key base:" "$cache_key_base" "debug"
	display_alert "Cache key:" "$cache_key" "debug"

	declare cache_dir_base="${SRC}/cache/patch/kernel-drivers"
	mkdir -p "${cache_dir_base}"

	declare cache_target_file="${cache_dir_base}/${cache_key}.patch"

	# outer scope variables:
	kernel_drivers_patch_file="${cache_target_file}"
	kernel_drivers_patch_hash="${cache_key}"

	# If the target file exists, we can skip the patch creation.
	if [[ -f "${cache_target_file}" ]]; then
		display_alert "Using cached drivers patch file for ${LINUXFAMILY}-${KERNEL_MAJOR_MINOR}" "${cache_key}" "cachehit"
		return
	fi

	display_alert "Creating patches for kernel drivers" "version: '${KERNEL_MAJOR_MINOR}' family: '${LINUXFAMILY}'" "info"

	# if it does _not_ exist, fist clear the base, so no old patches are left over
	run_host_command_logged rm -fv "${cache_dir_base}/${cache_key_base}*"

	# since it does not exist, go create it. this requires working tree.
	declare target_patch_file="${cache_target_file}"

	display_alert "Preparing patch for drivers" "version: ${KERNEL_MAJOR_MINOR} kernel_work_dir: ${kernel_work_dir}" "debug"

	kernel_drivers_prepare_harness "${kernel_work_dir}" "${kernel_git_revision}"
}

function kernel_drivers_prepare_harness() {
	declare kernel_work_dir="${1}"
	declare kernel_git_revision="${2}"
	declare -I target_patch_file # outer scope variable

	declare -a drivers=(
		driver_generic_bring_back_ipx
		driver_rtl8152_rtl8153
		driver_rtl8189ES
		driver_rtl8189FS
		driver_rtl8192EU
		driver_rtl8811_rtl8812_rtl8814_rtl8821
		driver_xradio_xr819
		driver_rtl8811CU_rtl8821C
		driver_rtl8188EU_rtl8188ETV
		driver_rtl88x2bu
		driver_rtl88x2cs
		driver_rtl8822cs_bt
		driver_rtl8723DS
		driver_rtl8723DU
		driver_rtl8822BS
	)

	# change cwd to the kernel working dir
	cd "${kernel_work_dir}" || exit_with_error "Failed to change directory to ${kernel_work_dir}"

	#run_host_command_logged git status
	run_host_command_logged git reset --hard "${kernel_git_revision}"
	# git: remove tracked files, but not those in .gitignore
	run_host_command_logged git clean -fd # no -x here

	for driver in "${drivers[@]}"; do
		display_alert "Preparing driver" "${driver}" "info"

		# reset variables used by each driver
		declare version="${KERNEL_MAJOR_MINOR}"
		declare kernel_work_dir="${1}"
		declare kernel_git_revision="${2}"
		# for compatibility with `master`-based code
		declare kerneldir="${kernel_work_dir}"
		declare EXTRAWIFI="yes" # forced! @TODO not really?

		# change cwd to the kernel working dir
		cd "${kernel_work_dir}" || exit_with_error "Failed to change directory to ${kernel_work_dir}"

		# invoke the driver; non-armbian-next code.
		"${driver}"

		# recover from possible cwd changes in the driver code
		cd "${kernel_work_dir}" || exit_with_error "Failed to change directory to ${kernel_work_dir}"
	done

	# git: check if there are modifications
	if [[ -n "$(git status --porcelain)" ]]; then
		display_alert "Drivers have modifications" "exporting patch into ${target_patch_file}" "info"
		export_changes_as_patch_via_git_format_patch
	else
		exit_with_error "Applying drivers didn't produce changes."
	fi
}

function export_changes_as_patch_via_git_format_patch() {
	# git: add all modifications
	run_host_command_logged git add .

	# git: commit the changes
	declare -a commit_params=(
		-m "drivers for ${LINUXFAMILY} version ${KERNEL_MAJOR_MINOR}"
		--author="${MAINTAINER} <${MAINTAINERMAIL}>"
	)
	declare -a commit_envs=(
		"GIT_COMMITTER_NAME=${MAINTAINER}"
		"GIT_COMMITTER_EMAIL=${MAINTAINERMAIL}"
	)
	run_host_command_logged env -i "${commit_envs[@]@Q}" git commit "${commit_params[@]@Q}"

	# export the commit as a patch
	declare formatpatch_params=(
		"-1" "--stdout"
		"--unified=3"               # force 3 lines of diff context
		"--keep-subject"            # do not add a prefix to the subject "[PATCH] "
		"--no-encode-email-headers" # do not encode email headers
		'--signature' "Armbian generated patch from drivers for kernel ${version} and family ${LINUXFAMILY}"
		'--stat=120'            # 'wider' stat output; default is 80
		'--stat-graph-width=10' # shorten the diffgraph graph part, it's too long
		"--zero-commit"         # Output an all-zero hash in each patch’s From header instead of the hash of the commit.
	)
	run_host_command_logged env -i git format-patch "${formatpatch_params[@]@Q}" > "${target_patch_file}"
}
