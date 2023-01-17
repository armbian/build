# for deb building.
function fakeroot_dpkg_deb_build() {
	display_alert "Building .deb package" "$*" "debug"

	declare -a orig_args=("$@")
	# find the first non-option argument
	declare first_arg
	for first_arg in "${orig_args[@]}"; do
		if [[ "${first_arg}" != -* ]]; then
			break
		fi
	done

	if [[ ! -d "${first_arg}" ]]; then
		exit_with_error "fakeroot_dpkg_deb_build: can't find source package directory: ${first_arg}"
	fi

	# Show the total human size of the source package directory.
	display_alert "Source package size" "${first_arg}: $(du -sh "${first_arg}" | cut -f1)" "debug"

	run_host_command_logged_raw fakeroot dpkg-deb -b "-Z${DEB_COMPRESS}" "${orig_args[@]}"
}
