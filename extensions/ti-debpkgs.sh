function post_repo_customize_image__install_ti_packages() {

	# Read JSON array into Bash array safely
	mapfile -t valid_suites < <(
		curl -s https://api.github.com/repos/TexasInstruments/ti-debpkgs/contents/dists |
			jq -r '.[].name'
	)
	display_alert "TI Repo has the following valid suites - ${valid_suites[@]}..."

	local ti_repo_suite=""
	local ti_candidate_suite
	local -a ti_candidate_suites=("${RELEASE}")

	if [[ -n "${TI_DEBPKGS_SUITE:-}" ]]; then
		ti_candidate_suites=("${TI_DEBPKGS_SUITE}")
	elif declare -p TI_DEBPKGS_FALLBACK_SUITES &> /dev/null; then
		ti_candidate_suites+=("${TI_DEBPKGS_FALLBACK_SUITES[@]}")
	fi

	for ti_candidate_suite in "${ti_candidate_suites[@]}"; do
		if printf '%s\n' "${valid_suites[@]}" | grep -qx "${ti_candidate_suite}"; then
			ti_repo_suite="${ti_candidate_suite}"
			break
		fi
	done

	if [[ -n "${ti_repo_suite}" ]]; then
		if [[ "${ti_repo_suite}" != "${RELEASE}" ]]; then
			display_alert "Using TI package suite '${ti_repo_suite}' for release '${RELEASE}'" "fallback requested by board config" "warn"
		fi

		# Get the sources file
		run_host_command_logged "mkdir -p \"$SDCARD/tmp\""
		run_host_command_logged "wget -qO $SDCARD/tmp/ti-debpkgs.sources https://raw.githubusercontent.com/TexasInstruments/ti-debpkgs/main/ti-debpkgs.sources"

		# Update suite in source file
		chroot_sdcard "sed -i 's/^Suites:.*/Suites: ${ti_repo_suite}/' /tmp/ti-debpkgs.sources"

		# Copy updated sources file into chroot
		chroot_sdcard "cp /tmp/ti-debpkgs.sources /etc/apt/sources.list.d/ti-debpkgs.sources"

		# Clean up inside the chroot
		chroot_sdcard "rm -f /tmp/ti-debpkgs.sources"

		chroot_sdcard "mkdir -p /etc/apt/preferences.d/"
		run_host_command_logged "cp \"$SRC/packages/bsp/ti/ti-debpkgs/ti-debpkgs\" \"$SDCARD/etc/apt/preferences.d/\""

		# Install packages
		if [[ ${#TI_PACKAGES[@]} -gt 0 ]]; then
			do_with_retries 3 chroot_sdcard_apt_get_update
			do_with_retries 3 chroot_sdcard_apt_get --no-install-recommends --allow-downgrades install "${TI_PACKAGES[@]}"
		fi

	else
		# Error if suite is not valid but continue building image anyway
		display_alert "Error: Detected OS suite '$RELEASE' is not valid based on TI package repository. Skipping!"
		display_alert "Valid Options Would Have Been: ${valid_suites[@]}"
	fi
}
