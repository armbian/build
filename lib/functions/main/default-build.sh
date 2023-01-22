# This does NOT run under the logging manager. We should invoke the do_with_logging wrapper for
# strategic parts of this. Attention: almost everything does it's own logging.
function main_default_build_single() {
	main_default_start_build # Has its own logging, prepares workdir, does prepare_host, aggregation, and

	main_default_build_packages # has its own logging sections # requires aggregation

	# build rootfs, if not only kernel. Again, read "KERNEL_ONLY" as if it was "PACKAGES_ONLY"
	if [[ "${KERNEL_ONLY}" != "yes" ]]; then
		display_alert "Building image" "${BOARD}" "target-started"
		build_rootfs_and_image # old "debootstrap-ng"; has its own logging sections.
		display_alert "Done building image" "${BOARD}" "target-reached"
	fi

	main_default_end_build

	if armbian_is_running_in_container; then
		BUILD_CONFIG='docker' # @TODO: this is not true, CLI handles this differently, gotta ask the CLI; this whole thing is inconsistent
	fi

	# Make it easy to repeat build by displaying build options used. Prepare array. @TODO this is inconsistent. Maybe something like the relaunch vars?
	local -a repeat_args=("./compile.sh" "${BUILD_CONFIG}" " BRANCH=${BRANCH}")
	[[ -n ${RELEASE} ]] && repeat_args+=("RELEASE=${RELEASE}")
	[[ -n ${BUILD_MINIMAL} ]] && repeat_args+=("BUILD_MINIMAL=${BUILD_MINIMAL}")
	[[ -n ${BUILD_DESKTOP} ]] && repeat_args+=("BUILD_DESKTOP=${BUILD_DESKTOP}")
	[[ -n ${KERNEL_ONLY} ]] && repeat_args+=("KERNEL_ONLY=${KERNEL_ONLY}")
	[[ -n ${KERNEL_CONFIGURE} ]] && repeat_args+=("KERNEL_CONFIGURE=${KERNEL_CONFIGURE}")
	[[ -n ${DESKTOP_ENVIRONMENT} ]] && repeat_args+=("DESKTOP_ENVIRONMENT=${DESKTOP_ENVIRONMENT}")
	[[ -n ${DESKTOP_ENVIRONMENT_CONFIG_NAME} ]] && repeat_args+=("DESKTOP_ENVIRONMENT_CONFIG_NAME=${DESKTOP_ENVIRONMENT_CONFIG_NAME}")
	[[ -n ${DESKTOP_APPGROUPS_SELECTED} ]] && repeat_args+=("DESKTOP_APPGROUPS_SELECTED=\"${DESKTOP_APPGROUPS_SELECTED}\"")
	[[ -n ${DESKTOP_APT_FLAGS_SELECTED} ]] && repeat_args+=("DESKTOP_APT_FLAGS_SELECTED=\"${DESKTOP_APT_FLAGS_SELECTED}\"")
	[[ -n ${COMPRESS_OUTPUTIMAGE} ]] && repeat_args+=("COMPRESS_OUTPUTIMAGE=${COMPRESS_OUTPUTIMAGE}")
	display_alert "Repeat Build Options" "${repeat_args[*]}" "ext" # * = expand array, space delimited, single-word.
}
