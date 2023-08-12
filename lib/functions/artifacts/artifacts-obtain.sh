#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function create_artifact_functions() {
	declare -a funcs=(
		"cli_adapter_pre_run" "cli_adapter_config_prep"
		"config_dump"
		"prepare_version"
		"get_default_oci_target"
		"is_available_in_local_cache" "is_available_in_remote_cache" "obtain_from_remote_cache"
		"deploy_to_remote_cache"
		"build_from_sources"
	)
	for func in "${funcs[@]}"; do
		declare impl_func="artifact_${chosen_artifact_impl}_${func}"
		if [[ $(type -t "${impl_func}") == function ]]; then
			declare cmd
			cmd="$(
				cat <<- ARTIFACT_DEFINITION
					function artifact_${func}() {
						display_alert "Calling artifact function" "${impl_func}() \$*" "debug"
						${impl_func} "\$@"
					}
				ARTIFACT_DEFINITION
			)"
			eval "${cmd}"
		else
			exit_with_error "Missing artifact implementation function '${impl_func}'"
		fi
	done

	# If ${chosen_artifact} is in ${DONT_BUILD_ARTIFACTS}, or if DONT_BUILD_ARTIFACTS contains 'any', override the build function with an error.
	if [[ "${DONT_BUILD_ARTIFACTS}" = *"${chosen_artifact}"* || "${DONT_BUILD_ARTIFACTS}" = *any* ]]; then
		display_alert "Artifact '${chosen_artifact}' is in DONT_BUILD_ARTIFACTS, overriding build function with error" "DONT_BUILD_ARTIFACTS=${chosen_artifact}" "debug"
		declare cmd
		cmd="$(
			cat <<- ARTIFACT_DEFINITION
				function artifact_build_from_sources() {
					exit_with_error "Artifact '${chosen_artifact}' is in DONT_BUILD_ARTIFACTS. This usually means that the artifact cache is not being hit because it is outdated."
				}
			ARTIFACT_DEFINITION
		)"
		eval "${cmd}"
	else
		display_alert "Artifact '${chosen_artifact}' is not in DONT_BUILD_ARTIFACTS, using default build function" "DONT_BUILD_ARTIFACTS!=${chosen_artifact}" "debug"
	fi
}

function initialize_artifact() {
	declare -g chosen_artifact="${1}"

	# cant be empty, or have spaces nor commas
	[[ "x${chosen_artifact}x" == "xx" ]] && exit_with_error "Artifact name is empty"
	[[ "${chosen_artifact}" == *" "* ]] && exit_with_error "Artifact name cannot contain spaces"
	[[ "${chosen_artifact}" == *","* ]] && exit_with_error "Artifact name cannot contain commas"

	armbian_register_artifacts
	declare -g chosen_artifact_impl="${ARMBIAN_ARTIFACTS_TO_HANDLERS_DICT["${chosen_artifact}"]}"
	[[ "x${chosen_artifact_impl}x" == "xx" ]] && exit_with_error "Unknown artifact '${chosen_artifact}'"
	display_alert "artifact" "${chosen_artifact} :: ${chosen_artifact_impl}()" "info"
	create_artifact_functions
}

function obtain_complete_artifact() {
	declare -g artifact_name="undetermined"
	declare -g artifact_type="undetermined"
	declare -g artifact_version="undetermined"
	declare -g artifact_version_reason="undetermined"
	declare -g artifact_final_version_reversioned="${REVISION}" # by default
	declare -g artifact_base_dir="undetermined"
	declare -g artifact_final_file="undetermined"
	declare -g artifact_final_file_basename="undetermined"
	declare -g artifact_full_oci_target="undetermined"
	declare -g artifact_deb_repo="undetermined"
	declare -g artifact_deb_arch="undetermined"
	declare -A -g artifact_map_packages=()
	declare -A -g artifact_map_debs=()
	declare -A -g artifact_map_debs_reversioned=()
	declare -a -g artifact_debs_reversion_functions=()

	# Contentious; it might be that prepare_version is complex enough to warrant more than 1 logging section.
	LOG_SECTION="artifact_prepare_version" do_with_logging artifact_prepare_version

	debug_var artifact_name
	debug_var artifact_type
	debug_var artifact_version
	debug_var artifact_version_reason

	# sanity checks. artifact_version/artifact_version_reason/artifact_final_file *must* be set
	[[ "x${artifact_name}x" == "xx" || "${artifact_name}" == "undetermined" ]] && exit_with_error "artifact_name is not set after artifact_prepare_version"
	[[ "x${artifact_type}x" == "xx" || "${artifact_type}" == "undetermined" ]] && exit_with_error "artifact_type is not set after artifact_prepare_version"
	[[ "x${artifact_version}x" == "xx" || "${artifact_version}" == "undetermined" ]] && exit_with_error "artifact_version is not set after artifact_prepare_version"
	[[ "x${artifact_version_reason}x" == "xx" || "${artifact_version_reason}" == "undetermined" ]] && exit_with_error "artifact_version_reason is not set after artifact_prepare_version"

	declare -a artifact_map_debs_values=()
	declare -a artifact_map_packages_values=()
	declare -a artifact_map_debs_keys=()
	declare -a artifact_map_packages_keys=()
	declare -a artifact_map_debs_reversioned_keys=()
	declare -a artifact_map_debs_reversioned_values=()

	# validate artifact_type... it must be one of the supported types
	case "${artifact_type}" in
		deb | deb-tar)
			# check artifact_base_dir and artifact_base_dir are 'undetermined', or bomb; deb/deb-tar shouldn't set those anymore
			[[ "${artifact_base_dir}" != "undetermined" ]] && exit_with_error "artifact ${artifact_name} is setting artifact_base_dir, legacy code, remove."
			[[ "${artifact_final_file}" != "undetermined" ]] && exit_with_error "artifact ${artifact_name} is setting artifact_final_file, legacy code, remove."

			# validate artifact_version begins with a digit when building deb packages; dpkg requires it
			[[ "${artifact_version}" =~ ^[0-9] ]] || exit_with_error "${artifact_type}: artifact_version '${artifact_version}' does not begin with a digit"
			# since it's a deb or deb-tar, validate deb-specific variables
			[[ "x${artifact_deb_repo}x" == "xx" || "${artifact_deb_repo}" == "undetermined" ]] && exit_with_error "artifact_deb_repo is not set after artifact_prepare_version"
			[[ "x${artifact_deb_arch}x" == "xx" || "${artifact_deb_arch}" == "undetermined" ]] && exit_with_error "artifact_deb_arch is not set after artifact_prepare_version"
			# validate there's at least one item in artifact_map_packages
			[[ "${#artifact_map_packages[@]}" -eq 0 ]] && exit_with_error "artifact_map_packages is empty after artifact_prepare_version"

			# Add the reversioning hash to the artifact_version
			declare artifact_reversioning_hash="undetermined"
			artifact_calculate_reversioning_hash
			declare artifact_reversioning_hash_short="${artifact_reversioning_hash:0:4}"
			artifact_version="${artifact_version}-R${artifact_reversioning_hash_short}"
			display_alert "Final artifact_version with reversioning hash" "${artifact_version}" "debug"

			debug_dict artifact_map_packages
			debug_dict artifact_map_debs
			debug_dict artifact_map_debs_reversioned

			# produce the mapped/reversioned deb info given the debs.
			declare one_artifact_deb_id one_artifact_deb_package
			declare -i debs_counter=0
			declare single_deb_hashed_rel_path
			for one_artifact_deb_id in "${!artifact_map_packages[@]}"; do
				one_artifact_deb_package="${artifact_map_packages["${one_artifact_deb_id}"]}"

				single_deb_hashed_rel_path="${artifact_deb_repo}/${one_artifact_deb_package}_${artifact_version}_${artifact_deb_arch}.deb"
				artifact_map_debs+=(["${one_artifact_deb_id}"]="${single_deb_hashed_rel_path}")

				declare artifact_deb_repo_prefix=""
				[[ "${artifact_deb_repo}" != "global" ]] && artifact_deb_repo_prefix="${artifact_deb_repo}/"

				artifact_map_debs_reversioned+=(["${one_artifact_deb_id}"]="${artifact_deb_repo_prefix}${one_artifact_deb_package}_${artifact_final_version_reversioned}_${artifact_deb_arch}__${artifact_version}.deb")
				debs_counter+=1
			done

			artifact_base_dir="${PACKAGES_HASHED_STORAGE}" # deb and deb-tar always use packages-hashed as the base dir
			# deb-tar:
			if [[ "${artifact_type}" == "deb-tar" ]]; then
				# fill in the artifact_final_file for deb-tar.
				artifact_final_file="${artifact_base_dir}/${artifact_name}_${artifact_version}_${artifact_deb_arch}.tar"
			else # deb, single-deb
				# bomb if we have more than one...
				[[ "${debs_counter}" -gt 1 ]] && exit_with_error "artifact_type '${artifact_type}' has more than one deb file. This is not supported."
				# just use the single deb rel path
				artifact_final_file="${artifact_base_dir}/${single_deb_hashed_rel_path}"
			fi

			debug_dict artifact_map_packages
			debug_dict artifact_map_debs
			debug_dict artifact_map_debs_reversioned

			# grab the the deb maps, and add them to plain arrays.
			artifact_map_debs_keys=("${!artifact_map_debs[@]}")
			artifact_map_debs_values=("${artifact_map_debs[@]}")
			artifact_map_packages_keys=("${!artifact_map_packages[@]}")
			artifact_map_packages_values=("${artifact_map_packages[@]}")
			artifact_map_debs_reversioned_keys=("${!artifact_map_debs_reversioned[@]}")
			artifact_map_debs_reversioned_values=("${artifact_map_debs_reversioned[@]}")

			;;
		tar.zst)
			# tar.zst (rootfs) must specify the directories directly, since we can't determine from deb info.
			[[ "x${artifact_base_dir}x" == "xx" || "${artifact_base_dir}" == "undetermined" ]] && exit_with_error "artifact_base_dir is not set after artifact_prepare_version"
			[[ "x${artifact_final_file}x" == "xx" || "${artifact_final_file}" == "undetermined" ]] && exit_with_error "artifact_final_file is not set after artifact_prepare_version"
			;;
		*)
			exit_with_error "artifact_type '${artifact_type}' is not supported"
			;;
	esac

	debug_var artifact_base_dir
	debug_var artifact_final_file

	# set those as outputs for GHA
	github_actions_add_output artifact_name "${artifact_name}"
	github_actions_add_output artifact_type "${artifact_type}"
	github_actions_add_output artifact_version "${artifact_version}"
	github_actions_add_output artifact_version_reason "${artifact_version_reason}"
	github_actions_add_output artifact_final_file "${artifact_final_file}"

	# ensure artifact_base_dir exists
	mkdir -p "${artifact_base_dir}"

	# compute artifact_final_file relative to ${SRC} but don't use realpath
	declare -g artifact_file_relative="${artifact_final_file#${SRC}/}"
	github_actions_add_output artifact_file_relative "${artifact_file_relative}"

	# just the file name, sans any path
	declare -g artifact_final_file_basename="undetermined"
	artifact_final_file_basename="$(basename "${artifact_final_file}")"
	github_actions_add_output artifact_final_file_basename "${artifact_final_file_basename}"

	debug_var artifact_final_file_basename
	debug_var artifact_file_relative

	# Determine OCI coordinates. OCI_TARGET_BASE overrides the default proposed by the artifact.
	# @TODO, store both, so we can check a custom one first, and then the default, one day.
	declare artifact_oci_target_base="undetermined"
	if [[ -n "${OCI_TARGET_BASE}" ]]; then
		artifact_oci_target_base="${OCI_TARGET_BASE}"
	else
		artifact_get_default_oci_target
	fi

	[[ -z "${artifact_oci_target_base}" ]] && exit_with_error "No artifact_oci_target_base defined."

	declare -g artifact_full_oci_target="${artifact_oci_target_base}${artifact_name}:${artifact_version}"

	# if CONFIG_DEFS_ONLY, dump JSON and exit
	if [[ "${CONFIG_DEFS_ONLY}" == "yes" ]]; then
		display_alert "artifact" "CONFIG_DEFS_ONLY is set, skipping artifact creation" "warn"
		artifact_dump_json_info
		exit 0
	fi

	declare -g artifact_exists_in_local_cache="undetermined"
	declare -g artifact_exists_in_local_reversioned_cache="undetermined"
	declare -g artifact_exists_in_remote_cache="undetermined"

	# Ignore both local and remote cache if we're deploying to remote or if ARTIFACT_IGNORE_CACHE=yes
	if [[ "${ARTIFACT_IGNORE_CACHE}" != "yes" && "${deploy_to_remote:-"no"}" != "yes" ]]; then

		# If NOT deploying to remote, check if the reversioned artifact exists in local cache.
		if [[ "${deploy_to_remote:-"no"}" != "yes" ]]; then
			LOG_SECTION="artifact_is_available_in_revisioned_local_cache" do_with_logging artifact_is_available_in_revisioned_local_cache
			debug_var artifact_exists_in_local_reversioned_cache
		fi

		# If it's not already reversioned in local cache, check if the artifact exists in local hashed cache and remote.
		if [[ "${artifact_exists_in_local_reversioned_cache}" != "yes" ]]; then

			LOG_SECTION="artifact_is_available_in_local_cache" do_with_logging artifact_is_available_in_local_cache
			debug_var artifact_exists_in_local_cache

			# If available in local cache, we're done (except for deb-tar which needs unpacking...)
			if [[ "${artifact_exists_in_local_cache}" == "yes" ]]; then
				display_alert "artifact" "exists in local cache: ${artifact_name} ${artifact_version}" "debug"
				LOG_SECTION="unpack_artifact_from_local_cache" do_with_logging unpack_artifact_from_local_cache
			else
				# If not available in local cache, check remote cache.
				LOG_SECTION="artifact_is_available_in_remote_cache" do_with_logging artifact_is_available_in_remote_cache
				debug_var artifact_exists_in_remote_cache

				if [[ "${artifact_exists_in_remote_cache}" == "yes" ]]; then
					display_alert "artifact" "exists in remote cache: ${artifact_name} ${artifact_version}" "debug"
					LOG_SECTION="artifact_obtain_from_remote_cache" do_with_logging artifact_obtain_from_remote_cache
					LOG_SECTION="unpack_artifact_from_local_cache" do_with_logging unpack_artifact_from_local_cache
					display_alert "artifact" "obtained from remote cache: ${artifact_name} ${artifact_version}" "cachehit"
				fi
			fi
		fi # endif artifact_exists_in_local_reversioned_cache!=yes
	fi  # endif ARTIFACT_IGNORE_CACHE!=yes

	# If it's not in any of the caches, build it.
	if [[ "${artifact_exists_in_local_cache}" != "yes" && "${artifact_exists_in_remote_cache}" != "yes" &&
		"${artifact_exists_in_local_reversioned_cache}" != "yes" ]]; then
		# Not found in any cache, so we need to build it.

		# Force high compression if deploying to remote...
		if [[ "${deploy_to_remote:-"no"}" == "yes" ]]; then
			declare -g DEB_COMPRESS="xz"
		fi

		# build the artifact from sources. has its own logging sections.
		artifact_build_from_sources

		# For interactive stuff like patching or configuring, we wanna stop here. No artifact file will be created.
		if [[ "${ARTIFACT_WILL_NOT_BUILD}" == "yes" ]]; then
			display_alert "artifact" "ARTIFACT_WILL_NOT_BUILD is set, stopping after non-build." "debug"
			return 0
		fi

		# pack the artifact to local cache (eg: for deb-tar)
		LOG_SECTION="pack_artifact_to_local_cache" do_with_logging pack_artifact_to_local_cache

		# Sanity check: the artifact_final_file should exist now.
		if [[ ! -f "${artifact_final_file}" ]]; then
			exit_with_error "Artifact file ${artifact_final_file} did not exist, after artifact_build_from_sources()."
		else
			display_alert "Artifact file exists" "${artifact_final_file} YESSS" "debug"
		fi
	fi

	if [[ "${deploy_to_remote:-"no"}" == "yes" ]]; then
		# deploying to remote cache: do the deploy and don't reversion, and remove the base dir
		LOG_SECTION="artifact_deploy_to_remote_cache" do_with_logging artifact_deploy_to_remote_cache

		# get rid of the artifact_base_dir so build machines don't gather trash over time.
		if [[ "${artifact_base_dir}" != "" && -d "${artifact_base_dir}" ]]; then
			display_alert "artifact uploaded to remote OK" "removing artifact_base_dir: '${artifact_base_dir}'" "info"
			# ignore errors; they might occur if the base dir is mounted (eg cache/rootfs), but are harmless.
			LOG_SECTION="artifact_remove_base_dir" do_with_logging run_host_command_logged rm -rvf "${artifact_base_dir}" "||" true
		fi
	else
		# not deploying to remote cache. reversion the artifact, unless that was found in caches.
		# reversioning removes the original in packages-hashed.
		debug_dict artifact_map_debs_reversioned
		LOG_SECTION="artifact_reversion_for_deployment" do_with_logging artifact_reversion_for_deployment
	fi
}

function artifact_dump_json_info() {
	declare -a wanted_vars=(
		artifact_name
		artifact_type
		artifact_deb_repo
		artifact_deb_arch
		artifact_version
		artifact_version_reason
		artifact_final_version_reversioned
		artifact_base_dir
		artifact_final_file
		artifact_final_file_basename
		artifact_file_relative
		artifact_full_oci_target

		# arrays
		artifact_map_debs_keys
		artifact_map_debs_values
		artifact_map_packages_keys
		artifact_map_packages_values
		artifact_map_debs_reversioned_keys
		artifact_map_debs_reversioned_values
	)

	declare -A ARTIFACTS_VAR_DICT=()

	for var in "${wanted_vars[@]}"; do
		declare declaration=""
		declaration="$(declare -p "${var}")"
		# Special handling for arrays. Syntax is not pretty, but works.
		if [[ "${declaration}" =~ "declare -a" ]]; then
			eval "declare ${var}_ARRAY=\"\${${var}[*]}\""
			ARTIFACTS_VAR_DICT["${var}_ARRAY"]="$(declare -p "${var}_ARRAY")"
		else
			ARTIFACTS_VAR_DICT["${var}"]="${declaration}"
		fi
	done

	display_alert "Dumping JSON" "for ${#ARTIFACTS_VAR_DICT[@]} variables" "ext"
	python3 "${SRC}/lib/tools/configdump2json.py" "--args" "${ARTIFACTS_VAR_DICT[@]}" # to stdout
}

function dump_artifact_config() {
	initialize_artifact "${WHAT}"

	declare -A -g artifact_input_variables=()
	debug_dict artifact_input_variables

	artifact_config_dump

	debug_dict artifact_input_variables

	# loop over the keys
	declare -a concat
	for key in "${!artifact_input_variables[@]}"; do
		# echo the key and its value
		concat+=("${key}=${artifact_input_variables[${key}]}")
	done

	declare -g artifact_input_vars="${concat[*]@Q}" # @Q to quote

}

# This is meant to be run after config, inside default build.
function build_artifact_for_image() {
	initialize_artifact "${WHAT}"

	# Make sure ORAS tooling is installed before starting.
	run_tool_oras

	# Detour: if building kernel, and KERNEL_CONFIGURE=yes, ignore artifact cache.
	if [[ "${WHAT}" == "kernel" && "${KERNEL_CONFIGURE}" == "yes" ]]; then
		display_alert "Ignoring artifact cache for kernel" "KERNEL_CONFIGURE=yes" "info"
		ARTIFACT_IGNORE_CACHE="yes" obtain_complete_artifact
	else
		obtain_complete_artifact
	fi

	return 0
}

function pack_artifact_to_local_cache() {
	if [[ "${artifact_type}" == "deb-tar" ]]; then
		declare -a files_to_tar=()
		run_host_command_logged tar -C "${artifact_base_dir}" -cf "${artifact_final_file}" "${artifact_map_debs[@]}"
		display_alert "Created deb-tar artifact" "deb-tar: ${artifact_final_file}" "info"
	fi
}

function unpack_artifact_from_local_cache() {
	if [[ "${artifact_type}" == "deb-tar" ]]; then
		declare any_missing="no"
		declare deb_name
		for deb_name in "${artifact_map_debs[@]}"; do
			declare new_name_full="${artifact_base_dir}/${deb_name}"
			if [[ ! -f "${new_name_full}" ]]; then
				display_alert "Unpacking artifact" "deb-tar: ${artifact_final_file_basename} missing: ${new_name_full}" "debug"
				any_missing="yes"
			fi
		done
		if [[ "${any_missing}" == "yes" ]]; then
			display_alert "Unpacking artifact" "deb-tar: ${artifact_final_file_basename}" "info"
			run_host_command_logged tar -C "${artifact_base_dir}" -xvf "${artifact_final_file}"
		fi
		# sanity check? did unpacking produce the expected files?
		declare any_missing="no"
		declare deb_name
		for deb_name in "${artifact_map_debs[@]}"; do
			declare new_name_full="${artifact_base_dir}/${deb_name}"
			if [[ ! -f "${new_name_full}" ]]; then
				display_alert "Unpacking artifact" "after unpack deb-tar: ${artifact_final_file_basename} missing: ${new_name_full}" "err"
				any_missing="yes"
			fi
		done
		if [[ "${any_missing}" == "yes" ]]; then
			display_alert "Files missing from deb-tar" "this is a bug, please report it. artifact_name: '${artifact_name}' artifact_version: '${artifact_version}'" "err"
		fi
		# either way, get rid of the .tar now.
		run_host_command_logged rm -fv "${artifact_final_file}"
	fi
	return 0
}

function upload_artifact_to_oci() {
	# check artifact_full_oci_target is set
	if [[ -z "${artifact_full_oci_target}" ]]; then
		exit_with_error "artifact_full_oci_target is not set"
	fi

	display_alert "Pushing to OCI" "'${artifact_final_file}' -> '${artifact_full_oci_target}'" "info"
	oras_push_artifact_file "${artifact_full_oci_target}" "${artifact_final_file}" "${artifact_name} - ${artifact_version} - ${artifact_version_reason} - type: ${artifact_type}"

	# If this is a deb-tar, delete the .tar after the upload. We won't ever need it again.
	if [[ "${artifact_type}" == "deb-tar" ]]; then
		display_alert "Deleting deb-tar after OCI deploy" "deb-tar: ${artifact_final_file_basename}" "debug"
		run_host_command_logged rm -fv "${artifact_final_file}"
	fi
}

function artifact_is_available_in_revisioned_local_cache() {
	artifact_exists_in_local_reversioned_cache="not_checked" # outer scope

	# only deb's and deb-tar's are reversioned.
	if [[ "${artifact_type}" != "deb-tar" && "${artifact_type}" != "deb" ]]; then
		return 0
	fi

	artifact_exists_in_local_reversioned_cache="no" # outer scope

	declare any_missing="no"
	declare one_artifact_deb_package
	for one_artifact_deb_package in "${!artifact_map_packages[@]}"; do
		# find the target dir and full path to the reversioned file
		declare deb_versioned_rel_path="${artifact_map_debs_reversioned["${one_artifact_deb_package}"]}"
		declare deb_versioned_full_path="${DEB_STORAGE}/${deb_versioned_rel_path}"
		if [[ ! -f "${deb_versioned_full_path}" ]]; then
			display_alert "Checking revisioned cache MISS" "deb pkg: ${one_artifact_deb_package} missing: ${deb_versioned_full_path}" "debug"
			any_missing="yes"
		else
			display_alert "Found reversioned deb HIT" "${deb_versioned_full_path}" "debug"
		fi
	done
	if [[ "${any_missing}" == "no" ]]; then
		display_alert "Checking revisioned cache" "deb-tar: ${artifact_final_file_basename} nothing missing" "debug"
		artifact_exists_in_local_reversioned_cache="yes" # outer scope
		return 0
	fi

	return 0
}

function is_artifact_available_in_local_cache() {
	artifact_exists_in_local_cache="no" # outer scope

	if [[ "${artifact_type}" == "deb-tar" ]]; then
		declare any_missing="no"
		declare deb_name
		for deb_name in "${artifact_map_debs[@]}"; do
			declare new_name_full="${artifact_base_dir}/${deb_name}"
			if [[ ! -f "${new_name_full}" ]]; then
				display_alert "Checking local cache" "deb-tar: ${artifact_final_file_basename} missing: ${new_name_full}" "debug"
				any_missing="yes"
			fi
		done
		if [[ "${any_missing}" == "no" ]]; then
			display_alert "Checking local cache" "deb-tar: ${artifact_final_file_basename} nothing missing" "debug"
			artifact_exists_in_local_cache="yes" # outer scope
			return 0
		fi
	fi

	if [[ -f "${artifact_final_file}" ]]; then
		artifact_exists_in_local_cache="yes" # outer scope
	fi
	return 0
}

function is_artifact_available_in_remote_cache() {
	# check artifact_full_oci_target is set
	if [[ -z "${artifact_full_oci_target}" ]]; then
		exit_with_error "artifact_full_oci_target is not set"
	fi

	declare oras_has_manifest="undetermined"
	declare oras_manifest_json="undetermined"
	declare oras_manifest_description="undetermined"
	oras_get_artifact_manifest "${artifact_full_oci_target}"

	display_alert "oras_has_manifest" "${oras_has_manifest}" "debug"
	display_alert "oras_manifest_description" "${oras_manifest_description}" "debug"
	display_alert "oras_manifest_json" "${oras_manifest_json}" "debug"

	if [[ "${oras_has_manifest}" == "yes" ]]; then
		display_alert "Artifact is available in remote cache" "${artifact_full_oci_target} - '${oras_manifest_description}'" "info"
		artifact_exists_in_remote_cache="yes"
	else
		display_alert "Artifact is not available in remote cache" "${artifact_full_oci_target}" "info"
		artifact_exists_in_remote_cache="no"
	fi

	return 0
}

function obtain_artifact_from_remote_cache() {
	display_alert "Obtaining artifact from remote cache" "${artifact_full_oci_target} into ${artifact_final_file_basename}" "info"
	oras_pull_artifact_file "${artifact_full_oci_target}" "${artifact_base_dir}" "${artifact_final_file_basename}"

	# if this is a 'deb', (not deb-tar, not tar.zst), OCI hasn't kept the directory structure, so move it into place.
	if [[ "${artifact_type}" == "deb" ]]; then
		declare final_file_dirname
		final_file_dirname="$(dirname "${artifact_final_file}")"
		mkdir -p "${final_file_dirname}"
		display_alert "Moving deb into place" "deb: ${artifact_final_file_basename}" "debug"
		run_host_command_logged mv "${artifact_base_dir}/${artifact_final_file_basename}" "${artifact_final_file}"
	fi

	# sanity check: after obtaining remotely, is it available locally? it should, otherwise there's some inconsistency.
	declare artifact_exists_in_local_cache="not-yet-after-obtaining-remotely"
	is_artifact_available_in_local_cache
	if [[ "${artifact_exists_in_local_cache}" == "no" ]]; then
		exit_with_error "Artifact is not available in local cache after obtaining remotely: ${artifact_full_oci_target} into '${artifact_base_dir}' file '${artifact_final_file_basename}'"
	fi

	return 0
}
