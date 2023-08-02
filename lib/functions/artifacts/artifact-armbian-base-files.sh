#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# tl;dr: this artifact is a replacement for the original distro's base-files.
# We find what is the latest version of the original distro's base-files.
# Then we download it, and we modify it to suit our needs.
# The artifact is named "armbian-base-files".
# But the package is still named "base-files", this is similar to what Linux Mint does for the same purpose.

function artifact_armbian-base-files_config_dump() {
	artifact_input_variables[RELEASE]="${RELEASE}"
	artifact_input_variables[ARCH]="${ARCH}"
}

function artifact_armbian-base-files_prepare_version() {
	: "${RELEASE:?RELEASE is not set}"
	: "${ARCH:?ARCH is not set}"

	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	declare short_hash_size=4
	declare fake_unchanging_base_version="1-${RELEASE}-1armbian1"

	declare found_package_version="undetermined" found_package_filename="undetermined" found_package_down_url="undetermined"
	sleep_seconds="15" do_with_retries 10 apt_find_upstream_package_version_and_download_url "base-files"

	# download the file, but write it to /dev/null (just for testing it is correct)
	# wget --timeout=15 --output-document=/dev/null "${found_package_down_url}" || exit_with_error "Could not download '${found_package_down_url}'"

	# Set readonly globals with the wanted info; will be used during the actual build of this artifact
	declare -g -r base_files_wanted_upstream_version="${found_package_version}"
	declare -g -r base_files_wanted_upstream_filename="${found_package_filename}"
	declare -g -r base_files_wanted_deb_down_url="${found_package_down_url}"

	# get the hashes of the lib/ bash sources involved.
	declare hash_files="undetermined"
	calculate_hash_for_bash_deb_artifact "artifacts/artifact-armbian-base-files.sh"
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	# outer scope
	artifact_version="${fake_unchanging_base_version}-B${bash_hash_short}"

	declare -a reasons=("Armbian armbian-base-files" "original ${RELEASE} version \"${base_files_wanted_upstream_version}\"" "framework bash hash \"${bash_hash}\"")

	artifact_version_reason="${reasons[*]}" # outer scope

	artifact_name="armbian-base-files-${RELEASE}-${ARCH}"
	artifact_type="deb"
	artifact_deb_repo="${RELEASE}" # release-specific repo (jammy etc)
	artifact_deb_arch="${ARCH}"    # arch-specific packages (arm64 etc)
	artifact_map_packages=(["armbian-base-files"]="base-files")

	# Important. Force the final reversioned version to contain the release name.
	# Otherwise, when publishing to a repo, pool/main/b/base-files/base-files_${REVISION}.deb will be the same across releases.
	artifact_final_version_reversioned="${REVISION}-${RELEASE}"

	# Register the function used to re-version the _contents_ of the base-files deb file.
	artifact_debs_reversion_functions+=("reversion_armbian-base-files_deb_contents")

	return 0
}

function artifact_armbian-base-files_build_from_sources() {
	LOG_SECTION="compile_armbian-base-files" do_with_logging compile_armbian-base-files
}

# Dont' wanna use a separate file for this. Keep it in here.
function compile_armbian-base-files() {
	: "${artifact_name:?artifact_name is not set}"
	: "${artifact_version:?artifact_version is not set}"
	: "${RELEASE:?RELEASE is not set}"
	: "${ARCH:?ARCH is not set}"
	: "${DISTRIBUTION:?DISTRIBUTION is not set}"

	display_alert "Creating base-files for ${DISTRIBUTION} release '${RELEASE}' arch '${ARCH}'" "${artifact_name} :: ${artifact_version}" "info"

	declare cleanup_id="" destination=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "base-files" cleanup_id destination # namerefs

	# Download the deb file
	declare deb_file="${destination}/${base_files_wanted_upstream_filename}"
	run_host_command_logged wget --no-verbose --timeout=60 --output-document="${deb_file}" "${base_files_wanted_deb_down_url}" || exit_with_error "Could not download '${base_files_wanted_deb_down_url}'"

	# Raw-Extract (with DEBIAN dir) the contents of the deb file into "${destination}"
	run_host_command_logged dpkg-deb --raw-extract "${deb_file}" "${destination}" || exit_with_error "Could not raw-extract '${deb_file}'"

	# Remove the .deb file
	rm -f "${deb_file}"

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		# Show the tree
		run_host_command_logged tree "${destination}"
		wait_for_disk_sync "after tree base-files"

		# Show the original control file, using batcat
		run_tool_batcat --file-name "${artifact_name}/DEBIAN/control" "${destination}/DEBIAN/control"

		# Show the original conffiles file, using batcat
		run_tool_batcat --file-name "${artifact_name}/DEBIAN/conffiles" "${destination}/DEBIAN/conffiles"
	fi

	# Let's hack at it. New Maintainer and Version...
	cat <<- EOD >> "${destination}/DEBIAN/control.new"
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Version: ${artifact_version}
	EOD
	# Keep everything else from original
	cat "${destination}/DEBIAN/control" | grep -vP '^(Maintainer|Version):' >> "${destination}/DEBIAN/control.new"

	# Replace 'Debian' with 'Armbian'.
	sed -i "s/Debian/${VENDOR}/g" "${destination}/DEBIAN/control.new"

	mv "${destination}/DEBIAN/control.new" "${destination}/DEBIAN/control"

	# Change etc/os-release, etc/issue, etc/issue.net, and DEBIAN/conffiles

	# Keep copies so we can diff
	cp "${destination}"/etc/os-release "${destination}"/etc/os-release.orig
	cp "${destination}"/etc/issue "${destination}"/etc/issue.orig
	cp "${destination}"/etc/issue.net "${destination}"/etc/issue.net.orig
	cp "${destination}"/DEBIAN/conffiles "${destination}"/DEBIAN/conffiles.orig

	# Attention: this is just a few base changes that don't involve "$REVISION".
	# More are done in reversion_armbian-base-files_deb_contents()
	cat <<- EOD >> "${destination}/etc/dpkg/origins/armbian"
		Vendor: ${VENDOR}
		Vendor-URL: ${VENDORURL}
		Bugs: ${VENDORBUGS}
		Parent: ${DISTRIBUTION}
	EOD
	sed -i "s|^HOME_URL=.*|HOME_URL=\"${VENDORURL}\"|" "${destination}"/etc/os-release
	sed -i "s|^SUPPORT_URL=.*|SUPPORT_URL=\"${VENDORSUPPORT}\"|" "${destination}"/etc/os-release
	sed -i "s|^BUG_REPORT_URL=.*|BUG_REPORT_URL=\"${VENDORBUGS}\"|" "${destination}"/etc/os-release
	sed -i "s|^PRIVACY_POLICY_URL=.*|PRIVACY_POLICY_URL=\"${VENDORPRIVACY}\"|" "${destination}"/etc/os-release
	sed -i "s|^LOGO=.*|LOGO=\"${VENDORLOGO}\"|" "${destination}"/etc/os-release

	# Remove content from motd: Ubuntu header, welcome text and news. We have our own
	rm -f "${destination}"/etc/update-motd.d/00-header
	sed -i "\/etc\/update-motd.d\/00-header/d" "${destination}/DEBIAN/conffiles"
	rm -f "${destination}"/etc/update-motd.d/10-help-text
	sed -i "\/etc\/update-motd.d\/10-help-text/d" "${destination}/DEBIAN/conffiles"
	rm -f "${destination}"/etc/update-motd.d/10-uname
	sed -i "\/etc\/update-motd.d\/10-uname/d" "${destination}/DEBIAN/conffiles"
	rm -f "${destination}"/etc/update-motd.d/50-motd-news
	sed -i "\/etc\/update-motd.d\/50-motd-news/d" "${destination}/DEBIAN/conffiles"

	# Remove Ubuntu default services
	[[ -f "${destination}"/lib/systemd/motd-news.service ]] && rm "${destination}"/lib/systemd/motd-news.service
	[[ -f "${destination}"/lib/systemd/motd-news.timer ]] && rm "${destination}"/lib/systemd/motd-news.timer

	# Adjust legal disclaimer and remove from conf files
	sed -i "\/etc\/legal/d" "${destination}/DEBIAN/conffiles"
	[[ -f "${destination}"/etc/legal ]] && sed -i "s/${DISTRIBUTION}/${VENDOR}/g" "${destination}"/etc/legal

	# Remove /etc/issue and /etc/issue.net from the DEBIAN/conffiles file
	sed -i '/^\/etc\/issue$/d' "${destination}"/DEBIAN/conffiles
	sed -i '/^\/etc\/issue.net$/d' "${destination}"/DEBIAN/conffiles

	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		# Show the results of the changing...
		run_tool_batcat --file-name "${artifact_name}/etc/os-release" "${destination}"/etc/os-release
		run_tool_batcat --file-name "${artifact_name}/etc/issue" "${destination}"/etc/issue
		run_tool_batcat --file-name "${artifact_name}/etc/issue.net" "${destination}"/etc/issue.net
		run_tool_batcat --file-name "${artifact_name}/DEBIAN/conffiles" "${destination}"/DEBIAN/conffiles

		# Show the diffs, use colors.
		run_host_command_logged diff --color=always -u "${destination}"/etc/os-release.orig "${destination}"/etc/os-release "||" true
		run_host_command_logged diff --color=always -u "${destination}"/etc/issue.orig "${destination}"/etc/issue "||" true
		run_host_command_logged diff --color=always -u "${destination}"/etc/issue.net.orig "${destination}"/etc/issue.net "||" true
		run_host_command_logged diff --color=always -u "${destination}"/DEBIAN/conffiles.orig "${destination}"/DEBIAN/conffiles "||" true
	fi

	# Remove the .orig files
	rm -f "${destination}"/etc/os-release.orig "${destination}"/etc/issue.orig "${destination}"/etc/issue.net.orig "${destination}"/DEBIAN/conffiles.orig

	# Done, pack it.
	fakeroot_dpkg_deb_build "${destination}" "armbian-base-files"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}

# Used to reversion the artifact contents.
function reversion_armbian-base-files_deb_contents() {
	display_alert "Reversioning" "reversioning base-files CONTENTS: '$*'" "debug"

	declare orig_distro_release="${RELEASE}"

	artifact_deb_reversion_unpack_data_deb
	: "${data_dir:?data_dir is not set}"

	# Change the PRETTY_NAME and add ARMBIAN_PRETTY_NAME in os-release, and change issue, issue.net
	echo "ARMBIAN_PRETTY_NAME=\"${VENDOR} ${REVISION} ${orig_distro_release}\"" >> "${data_dir}"/etc/os-release
	echo -e "${VENDOR} ${REVISION} ${orig_distro_release} \\l \n" > "${data_dir}"/etc/issue
	echo -e "${VENDOR} ${REVISION} ${orig_distro_release}" > "${data_dir}"/etc/issue.net
	sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"${VENDOR} $REVISION ${orig_distro_release}\"/" "${data_dir}"/etc/os-release

	# Show results if debugging
	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		run_tool_batcat --file-name "/etc/os-release.sh" "${data_dir}"/etc/os-release
		run_tool_batcat --file-name "/etc/issue" "${data_dir}"/etc/issue
		run_tool_batcat --file-name "/etc/issue.net" "${data_dir}"/etc/issue.net
	fi

	artifact_deb_reversion_repack_data_deb

	return 0
}

function artifact_armbian-base-files_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_armbian-base-files_cli_adapter_config_prep() {
	: "${RELEASE:?RELEASE is not set}"
	: "${BOARD:?BOARD is not set}"

	# there is no need for aggregation here, although RELEASE is required.
	use_board="yes" allow_no_family="no" skip_kernel="no" prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.
}

function artifact_armbian-base-files_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/armbian/os/"
}

function artifact_armbian-base-files_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_armbian-base-files_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_armbian-base-files_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_armbian-base-files_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
