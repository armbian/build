function post_repo_customize_image__install_ti_packages() {
	local ti_repo_suite=""
	local ti_candidate_suite
	local -a ti_candidate_suites=("${RELEASE}")
	local ti_repo_url="https://TexasInstruments.github.io/ti-debpkgs"

	if [[ -n "${TI_DEBPKGS_SUITE:-}" ]]; then
		ti_candidate_suites=("${TI_DEBPKGS_SUITE}")
	elif declare -p TI_DEBPKGS_FALLBACK_SUITES &> /dev/null; then
		ti_candidate_suites+=("${TI_DEBPKGS_FALLBACK_SUITES[@]}")
	fi

	for ti_candidate_suite in "${ti_candidate_suites[@]}"; do
		if [[ ! "${ti_candidate_suite}" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
			display_alert "Ignoring invalid TI package suite" "${ti_candidate_suite}" "warn"
			continue
		fi

		if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
			--connect-timeout 15 --max-time 60 -o /dev/null \
			"${ti_repo_url}/dists/${ti_candidate_suite}/Release"; then
			ti_repo_suite="${ti_candidate_suite}"
			break
		fi
	done

	if [[ -z "${ti_repo_suite}" ]]; then
		if ti_debpkgs_rogue_requested; then
			display_alert "TI package suite is unavailable" "tried: ${ti_candidate_suites[*]}; required for TI Rogue" "err"
			return 1
		fi

		display_alert "TI package suite is unavailable" "tried: ${ti_candidate_suites[*]}; skipping optional TI packages" "warn"
		return 0
	fi

	if [[ "${ti_repo_suite}" != "${RELEASE}" ]]; then
		display_alert "Using TI package suite '${ti_repo_suite}' for release '${RELEASE}'" "fallback requested by board config" "warn"
	fi

	# Get the sources file
	run_host_command_logged "mkdir -p \"$SDCARD/tmp\""
	run_host_command_logged "wget -qO $SDCARD/tmp/ti-debpkgs.sources https://raw.githubusercontent.com/TexasInstruments/ti-debpkgs/main/ti-debpkgs.sources"

	# Update suite in source file
	chroot_sdcard "sed -i 's/^Suites:.*/Suites: ${ti_repo_suite}/' /tmp/ti-debpkgs.sources"
	chroot_sdcard "grep -qx 'Suites: ${ti_repo_suite}' /tmp/ti-debpkgs.sources"

	# Copy updated sources file into chroot
	chroot_sdcard "cp /tmp/ti-debpkgs.sources /etc/apt/sources.list.d/ti-debpkgs.sources"

	# Clean up inside the chroot
	chroot_sdcard "rm -f /tmp/ti-debpkgs.sources"

	chroot_sdcard "mkdir -p /etc/apt/preferences.d/"
	run_host_command_logged "cp \"$SRC/packages/bsp/ti/ti-debpkgs/ti-debpkgs\" \"$SDCARD/etc/apt/preferences.d/\""

	# Remove all ti-img-rogue-* packages if GPU_SUPPORT is not yes
	local -a ti_packages_for_image=()
	local ti_package
	for ti_package in "${TI_PACKAGES[@]}"; do
		if [[ "${GPU_SUPPORT:-no}" != "yes" ]]; then
			case "${ti_package}" in
				ti-img-rogue-*)
					display_alert "Skipping TI Rogue package" "${ti_package}; GPU_SUPPORT is not yes" "debug"
					continue
					;;
			esac
		fi
		ti_packages_for_image+=("${ti_package}")
	done

	# Install packages
	if [[ ${#ti_packages_for_image[@]} -gt 0 ]]; then
		do_with_retries 3 chroot_sdcard_apt_get_update
		do_with_retries 3 chroot_sdcard_apt_get --no-install-recommends --allow-downgrades install "${ti_packages_for_image[@]}"
		if ti_debpkgs_rogue_requested; then
			build_ti_rogue_dkms_for_image
			ti_debpkgs_configure_rogue_module
		fi
	fi
}

function ti_debpkgs_has_rogue_packages() {
	local ti_package

	for ti_package in "${TI_PACKAGES[@]}"; do
		case "${ti_package}" in
			ti-img-rogue-*) return 0 ;;
		esac
	done

	return 1
}

function ti_debpkgs_count_rogue_dkms_packages() {
	local ti_package
	local count=0

	for ti_package in "${TI_PACKAGES[@]}"; do
		case "${ti_package}" in
			ti-img-rogue-driver-*-dkms) count=$((count + 1)) ;;
		esac
	done

	printf '%d\n' "${count}"
}

function ti_debpkgs_rogue_requested() {
	[[ "${GPU_SUPPORT:-no}" == "yes" ]] && ti_debpkgs_has_rogue_packages
}

function extension_finish_config__install_kernel_headers_for_ti_rogue_dkms() {
	ti_debpkgs_rogue_requested || return 0

	local rogue_dkms_count
	rogue_dkms_count="$(ti_debpkgs_count_rogue_dkms_packages)"
	if [[ "${rogue_dkms_count}" -ne 1 ]]; then
		display_alert "Invalid TI Rogue package configuration" "expected exactly one explicit Rogue DKMS package, found ${rogue_dkms_count}" "err"
		return 1
	fi

	if [[ "${KERNEL_HAS_WORKING_HEADERS:-no}" != "yes" ]]; then
		display_alert "Kernel headers are unavailable" "cannot build TI Rogue DKMS for ${BOARD}" "err"
		return 1
	fi

	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes" "TI Rogue DKMS" "debug"
}

function build_ti_rogue_dkms_for_image() {
	ti_debpkgs_rogue_requested || return 0

	if [[ "${INSTALL_HEADERS:-no}" != "yes" || "${KERNEL_HAS_WORKING_HEADERS:-no}" != "yes" ]]; then
		display_alert "Cannot build TI Rogue DKMS" "working target headers are required" "err"
		return 1
	fi

	local target_kver="${IMAGE_INSTALLED_KERNEL_VERSION:-}"
	if [[ -z "${target_kver}" ]]; then
		display_alert "Cannot determine target kernel version" "TI Rogue DKMS" "err"
		return 1
	fi
	if [[ "${target_kver}" != *"-${BRANCH}-${LINUXFAMILY}" ]]; then
		target_kver+="-${BRANCH}-${LINUXFAMILY}"
	fi

	declare -g if_error_detail_message="TI Rogue DKMS build failed for ${target_kver}"
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/ti-img-rogue-driver/*/build/make.log")
	display_alert "Building TI Rogue DKMS" "${target_kver}" "info"
	use_clean_environment="yes" chroot_sdcard "dkms autoinstall --verbose --kernelver ${target_kver}"
	chroot_sdcard "find /lib/modules/${target_kver} -type f -name 'pvrsrvkm.ko*' -print -quit | grep -q ."
	chroot_sdcard "depmod -a ${target_kver}"
}

function ti_debpkgs_configure_rogue_module() {
	run_host_command_logged "mkdir -p ${SDCARD}/etc/modules-load.d ${SDCARD}/etc/modprobe.d"
	cat > "${SDCARD}/etc/modules-load.d/ti-rogue.conf" << 'EOF'
# TI's out-of-tree Rogue PowerVR driver for supported K3 GPUs.
pvrsrvkm
EOF
	cat > "${SDCARD}/etc/modprobe.d/blacklist-upstream-powervr.conf" << 'EOF'
# Prefer TI's Rogue stack on K3 images configured with GPU_SUPPORT.
# The upstream driver's K3 coverage and performance vary, and it can bind first.
blacklist powervr
EOF
	display_alert "Configured TI Rogue module loading" "pvrsrvkm; upstream powervr blacklisted" "info"
}
