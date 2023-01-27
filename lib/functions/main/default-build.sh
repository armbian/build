# This does NOT run under the logging manager.
function full_build_packages_rootfs_and_image() {

	assert_requires_aggregation # Bombs if aggregation has not run

	main_default_build_packages # has its own logging sections # requires aggregation

	# build rootfs, if not only kernel. Again, read "KERNEL_ONLY" as if it was "PACKAGES_ONLY"
	if [[ "${KERNEL_ONLY}" != "yes" ]]; then
		display_alert "Building image" "${BOARD}" "target-started"
		build_rootfs_and_image # old "debootstrap-ng"; has its own logging sections.
		display_alert "Done building image" "${BOARD}" "target-reached"
	fi
}

function do_with_default_build() {
	main_default_start_build # Has its own logging, prepares workdir, does prepare_host, aggregation, and
	"${@}"
	main_default_end_build
}
