# @description Builds the `v4l2loopback` virtual-camera kernel module via DKMS in the chroot, installing `v4l2loopback-dkms`, `v4l2loopback-utils`, and `v4l-utils`. Forces `INSTALL_HEADERS=yes` and requires a kernel with a working headers package. Skipped on minimal CLI images and on kernels 7.2 or newer, where the module no longer builds.

function extension_finish_config__build_v4l2loopback_dkms_kernel_module() {
	# Deny on minimal CLI images
	if [[ "${BUILD_MINIMAL}" == "yes" ]]; then
		display_alert "Extension: ${EXTENSION}" "skip installation in minimal images" "warn"
		return 0
	fi
	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping v4l2loopback-dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with v4l2loopback-dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__build_v4l2loopback_dkms_kernel_module() {
	if linux-version compare "${KERNEL_MAJOR_MINOR}" ge 7.2; then
		display_alert "Kernel version is too recent" "skipping v4l2loopback-dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0

	# v4l2loopback only builds against current kernels from 0.15.3 onwards. Earlier releases
	# call v4l2_fh_add() with the pre-signature-change argument count and fail the DKMS build
	# with "too few arguments to function 'v4l2_fh_add'". Debian trixie still ships 0.15.0-2 in
	# main, so gate on the apt candidate version and skip (rather than fail the whole build)
	# when only a too-old package is available.
	declare -r v4l2loopback_min_version="0.15.3"
	# The host-side apt lists are bind-mounted into the chroot only for the duration of a
	# chroot_sdcard_apt_get* call, and the image's own /var/lib/apt/lists is not populated
	# until much later in the build (apt_lists_copy_from_host_to_image_and_update). Asking
	# apt-cache directly at this point therefore sees an empty index and answers nothing at
	# all. Go through the apt-aware runner so the lists are mounted, and redirect to a file
	# we read back host-side, since the runner logs stdout rather than returning it. That
	# runner is also what pins LC_ALL=C, keeping "Candidate:" parseable.
	declare -r v4l2loopback_policy_file="/tmp/.v4l2loopback-apt-policy"
	declare v4l2loopback_candidate=""
	declare v4l2loopback_policy_rc=0
	# Clear any leftover first: if the runner dies before the redirect is even set up, a
	# stale file must not be read as this query's answer and skip the extension on it.
	run_host_command_logged rm -f "${SDCARD}${v4l2loopback_policy_file}"
	# Keep the call out of errexit's reach. apt-cache itself exits 0 even for an unknown
	# package, but the runner around it can fail (apt-cacher-ng restart, the cache bind
	# mounts, the chroot itself), and a bare call would abort the whole build here instead
	# of falling through to the inconclusive path below.
	chroot_sdcard_custom_with_apt_logic "apt-cache" policy v4l2loopback-dkms "> ${v4l2loopback_policy_file}" ||
		v4l2loopback_policy_rc=$?
	if [[ "${v4l2loopback_policy_rc}" != "0" ]]; then
		display_alert "Querying apt for v4l2loopback-dkms failed" "rc=${v4l2loopback_policy_rc}; ${EXTENSION}" "warn"
	elif [[ -f "${SDCARD}${v4l2loopback_policy_file}" ]]; then
		# Same reasoning for the parse: an unreadable file leaves the candidate empty and
		# takes the inconclusive path, rather than aborting the build from a subshell.
		if ! v4l2loopback_candidate="$(awk '/Candidate:/ {print $2; exit}' "${SDCARD}${v4l2loopback_policy_file}")"; then
			v4l2loopback_candidate=""
		fi
	fi
	# Unconditional: a failed query can still have left a partial file in the rootfs.
	run_host_command_logged rm -f "${SDCARD}${v4l2loopback_policy_file}"
	if [[ "${v4l2loopback_candidate}" == "(none)" ]]; then
		display_alert "v4l2loopback-dkms not available from apt" "skipping ${EXTENSION}" "warn"
		return 0
	fi
	if [[ -z "${v4l2loopback_candidate}" ]]; then
		# Inconclusive, not negative. Skipping here would silently drop the module from the
		# image behind a single warning line, so install as before and let apt be the judge.
		display_alert "Could not read v4l2loopback-dkms apt candidate version" "installing anyway; ${EXTENSION}" "warn"
	elif ! dpkg --compare-versions "${v4l2loopback_candidate}" ge "${v4l2loopback_min_version}"; then
		display_alert "v4l2loopback-dkms ${v4l2loopback_candidate} < ${v4l2loopback_min_version}, won't build on kernel v${KERNEL_MAJOR_MINOR}" "skipping ${EXTENSION}" "warn"
		return 0
	fi

	display_alert "Install v4l2loopback-dkms packages, will build kernel module in chroot" "${EXTENSION}" "info"
	declare -g if_error_detail_message="v4l2loopback-dkms build failed, extension 'v4l2loopback-dkms'"
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/v4l2loopback*/*/build/*.log")
	use_clean_environment="yes" chroot_sdcard_apt_get_install "v4l2loopback-dkms v4l2loopback-utils v4l-utils"
}
