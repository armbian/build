function extension_prepare_config__add_packages() {
	if [[ ${#TI_PACKAGES[@]} -gt 0 ]] ; then
		add_packages_to_image "${TI_PACKAGES[@]}"
	fi
}

function post_armbian_repo_customize_image__install_ti_packages() {
	
    # Read JSON array into Bash array safely
	mapfile -t valid_suites < <(
		curl -s https://api.github.com/repos/TexasInstruments/ti-debpkgs/contents/dists |
		jq -r '.[].name'
	)
	display_alert "TI Repo has the following valid suites - ${valid_suites[@]}..."

	if printf '%s\n' "${valid_suites[@]}" | grep -qx "${RELEASE}"; then
		# Get the sources file
		run_host_command_logged "mkdir -p \"$SDCARD/tmp\""
		run_host_command_logged "wget -qO $SDCARD/tmp/ti-debpkgs.sources https://raw.githubusercontent.com/TexasInstruments/ti-debpkgs/main/ti-debpkgs.sources"

		# Update suite in source file
		chroot_sdcard "sed -i 's/bookworm/${RELEASE}/g' /tmp/ti-debpkgs.sources"

		# Copy updated sources file into chroot
		chroot_sdcard "cp /tmp/ti-debpkgs.sources /etc/apt/sources.list.d/ti-debpkgs.sources"

		# Clean up inside the chroot
		chroot_sdcard "rm -f /tmp/ti-debpkgs.sources"

		chroot_sdcard "mkdir -p /etc/apt/preferences.d/"
		run_host_command_logged "cp \"$SRC/packages/bsp/ti/ti-debpkgs/ti-debpkgs\" \"$SDCARD/etc/apt/preferences.d/\""

	else
		# Error if suite is not valid but continue building image anyway
		display_alert "Error: Detected OS suite '$RELEASE' is not valid based on TI package repository. Skipping!"
		display_alert "Valid Options Would Have Been: ${valid_suites[@]}"
	fi
}
