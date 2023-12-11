#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

function artifact_reversion_for_deployment() {
	standard_artifact_reversion_for_deployment "${artifact_debs_reversion_functions[@]}"
}

function artifact_calculate_reversioning_hash() {
	declare hash_functions="undetermined"
	declare -a all_functions=("standard_artifact_reversion_for_deployment" "standard_artifact_reversion_for_deployment_one_deb")
	all_functions+=("artifact_deb_reversion_unpack_data_deb" "artifact_deb_reversion_repack_data_deb")
	all_functions+=("${artifact_debs_reversion_functions[@]}")
	calculate_hash_for_function_bodies "${all_functions[@]}" # sets hash_functions
	artifact_reversioning_hash="${hash_functions}"           # outer scope
	return 0
}

function standard_artifact_reversion_for_deployment() {
	display_alert "Reversioning package" "re-version '${artifact_name}(${artifact_type})::${artifact_version}' to '${artifact_final_version_reversioned}'" "info"

	declare artifact_mapped_deb one_artifact_deb_package
	for one_artifact_deb_package in "${!artifact_map_packages[@]}"; do
		# find the target dir and full path to the reversioned file
		declare deb_versioned_rel_path="${artifact_map_debs_reversioned["${one_artifact_deb_package}"]}"
		declare deb_versioned_full_path="${DEB_STORAGE}/${deb_versioned_rel_path}"
		declare deb_versioned_dirname
		deb_versioned_dirname="$(dirname "${deb_versioned_full_path}")"

		run_host_command_logged mkdir -p "${deb_versioned_dirname}"

		# since the full versioned path includes the original hash, if the file already exists, we can trust
		# it's the correct one, and skip reversioning.
		# do touch the file, so mtime reflects it is wanted, and later delete old files to keep junk under control
		if [[ -f "${deb_versioned_full_path}" ]]; then
			display_alert "Skipping reversioning" "deb: ${deb_versioned_full_path} already exists" "debug"
			run_host_command_logged touch "${deb_versioned_full_path}"
			continue
		fi

		declare artifact_mapped_deb="${artifact_map_debs["${one_artifact_deb_package}"]}"
		declare hashed_storage_deb_full_path="${PACKAGES_HASHED_STORAGE}/${artifact_mapped_deb}"

		if [[ ! -f "${hashed_storage_deb_full_path}" ]]; then
			exit_with_error "hashed storage does not have ${hashed_storage_deb_full_path}"
		fi

		display_alert "Found hashed storage file" "'${artifact_mapped_deb}': ${hashed_storage_deb_full_path}" "debug"

		# call function for each deb, pass parameters
		standard_artifact_reversion_for_deployment_one_deb "${@}"

		# make sure reversioning produced the expected file
		if [[ ! -f "${deb_versioned_full_path}" ]]; then
			exit_with_error "reversioning did not produce the expected file: ${deb_versioned_full_path}"
		fi

		# Unless KEEP_HASHED_DEB_ARTIFACTS=yes, get rid of the original packages-hashed file, since we don't need it anymore.
		# KEEP_HASHED_DEB_ARTIFACTS=yes is set by 'download-artifact' CLI command.
		if [[ "${KEEP_HASHED_DEB_ARTIFACTS}" != "yes" ]]; then
			run_host_command_logged rm -fv "${hashed_storage_deb_full_path}"
		else
			display_alert "Keeping and touching hashed storage file" "KEEP_HASHED_DEB_ARTIFACTS=yes: ${hashed_storage_deb_full_path}" "info"
			# touch it so that it's timestamp is updated. we can later delete old files from packages-hashed to keep junk under control
			run_host_command_logged touch "${hashed_storage_deb_full_path}"
		fi
	done

	return 0
}

function standard_artifact_reversion_for_deployment_one_deb() {
	display_alert "Will repack" "one_artifact_deb_package: ${one_artifact_deb_package}" "debug"
	display_alert "Will repack" "hashed_storage_deb_full_path: ${hashed_storage_deb_full_path}" "debug"
	display_alert "Will repack" "deb_versioned_full_path: ${deb_versioned_full_path}" "debug"
	display_alert "Will repack" "artifact_version: ${artifact_version}" "debug"

	declare cleanup_id="" unpack_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "reversion-${artifact_name}" cleanup_id unpack_dir # namerefs

	declare deb_contents_dir="${unpack_dir}/deb-contents"
	mkdir -p "${deb_contents_dir}"

	# unpack the hashed_storage_deb_full_path .deb, which is just an "ar" file, to the deb_contents_dir
	run_host_command_logged ar x "${hashed_storage_deb_full_path}" --output="${deb_contents_dir}"

	# find out if compressed or not, and store for future recompressing
	control_compressed=""
	if [[ -f "${deb_contents_dir}/control.tar.xz" ]]; then
		control_compressed=".xz"
		run_host_command_logged xz -d "${deb_contents_dir}/control.tar.xz" # decompress
	fi

	# untar the control into its own specific dir
	declare control_dir="${unpack_dir}/control"
	mkdir -p "${control_dir}"
	run_host_command_logged tar -xf "${deb_contents_dir}/control.tar" --directory="${control_dir}"

	# prepare for unpacking the data tarball as well
	declare data_dir="${unpack_dir}/data"
	mkdir -p "${data_dir}"
	declare data_compressed=""
	if [[ -f "${deb_contents_dir}/data.tar.xz" ]]; then
		data_compressed=".xz"
	fi

	# Hack at the control file...
	declare control_file="${control_dir}/control"
	declare control_file_new="${control_dir}/control.new"

	# Replace "Version: " field with our own
	sed -e "s/^Version: .*/Version: ${artifact_final_version_reversioned}/" "${control_file}" > "${control_file_new}"
	echo "Armbian-Original-Hash: ${artifact_version}" >> "${control_file_new}" # non-standard field.

	for one_reversion_function_name in "${@}"; do
		display_alert "reversioning" "call custom function: '${one_reversion_function_name}'" "debug"
		"${one_reversion_function_name}" "${one_artifact_deb_package}"
	done

	# Show a nice diff using batcat if debugging
	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		diff -u "${control_file}" "${control_file_new}" > "${unpack_dir}/control.diff" || true
		run_tool_batcat "${unpack_dir}/control.diff"
	fi

	# Move new control on top of old
	run_host_command_logged mv "${control_file_new}" "${control_file}"

	run_host_command_logged rm "${deb_contents_dir}/control.tar"

	cd "${control_dir}" || exit_with_error "cray-cray about control_dir ${control_dir}"
	run_host_command_logged tar cf "${deb_contents_dir}/control.tar" .

	# if it was compressed to begin with, recompress...
	if [[ "${control_compressed}" == ".xz" ]]; then
		run_host_command_logged xz "${deb_contents_dir}/control.tar"
	fi

	# re-ar the whole .deb back in place, using the new version for filename.
	run_host_command_logged ar rcs "${deb_versioned_full_path}" \
		"${deb_contents_dir}/debian-binary" \
		"${deb_contents_dir}/control.tar${control_compressed}" \
		"${deb_contents_dir}/data.tar${data_compressed}"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early

	return 0
}

function artifact_deb_reversion_unpack_data_deb() {
	if [[ "${data_compressed}" == ".xz" ]]; then
		run_host_command_logged xz -d "${deb_contents_dir}/data.tar.xz" # decompress
	fi

	run_host_command_logged tar -xf "${deb_contents_dir}/data.tar" --directory="${data_dir}"
}

function artifact_deb_reversion_repack_data_deb() {
	run_host_command_logged rm "${deb_contents_dir}/data.tar"
	cd "${data_dir}" || exit_with_error "cray-cray about data_dir ${data_dir}"
	run_host_command_logged tar cf "${deb_contents_dir}/data.tar" .

	# if it was compressed to begin with, recompress...
	if [[ "${data_compressed}" == ".xz" ]]; then
		run_host_command_logged xz "${deb_contents_dir}/data.tar"
	fi
}
