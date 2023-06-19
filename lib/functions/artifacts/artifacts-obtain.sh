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
	: "${artifact_prefix_version:?artifact_prefix_version is not set}"

	declare -g artifact_name="undetermined"
	declare -g artifact_type="undetermined"
	declare -g artifact_version="undetermined"
	declare -g artifact_version_reason="undetermined"
	declare -g artifact_base_dir="undetermined"
	declare -g artifact_final_file="undetermined"
	declare -g artifact_final_file_basename="undetermined"
	declare -g artifact_full_oci_target="undetermined"
	declare -A -g artifact_map_packages=()
	declare -A -g artifact_map_debs=()

	# Check if REVISION is set, otherwise exit_with_error
	[[ "x${REVISION}x" == "xx" ]] && exit_with_error "REVISION is not set"

	# Contentious; it might be that prepare_version is complex enough to warrant more than 1 logging section.
	LOG_SECTION="artifact_prepare_version" do_with_logging artifact_prepare_version

	debug_var artifact_name
	debug_var artifact_type
	debug_var artifact_version
	debug_var artifact_version_reason
	debug_var artifact_base_dir
	debug_var artifact_final_file
	debug_dict artifact_map_packages
	debug_dict artifact_map_debs

	# sanity checks. artifact_version/artifact_version_reason/artifact_final_file *must* be set
	[[ "x${artifact_name}x" == "xx" || "${artifact_name}" == "undetermined" ]] && exit_with_error "artifact_name is not set after artifact_prepare_version"
	[[ "x${artifact_type}x" == "xx" || "${artifact_type}" == "undetermined" ]] && exit_with_error "artifact_type is not set after artifact_prepare_version"
	[[ "x${artifact_version}x" == "xx" || "${artifact_version}" == "undetermined" ]] && exit_with_error "artifact_version is not set after artifact_prepare_version"
	[[ "x${artifact_version_reason}x" == "xx" || "${artifact_version_reason}" == "undetermined" ]] && exit_with_error "artifact_version_reason is not set after artifact_prepare_version"
	[[ "x${artifact_base_dir}x" == "xx" || "${artifact_base_dir}" == "undetermined" ]] && exit_with_error "artifact_base_dir is not set after artifact_prepare_version"
	[[ "x${artifact_final_file}x" == "xx" || "${artifact_final_file}" == "undetermined" ]] && exit_with_error "artifact_final_file is not set after artifact_prepare_version"

	# validate artifact_version begins with artifact_prefix_version when building deb packages (or deb-tar)
	if [[ "${artifact_type}" != "tar.zst" ]]; then
		[[ "${artifact_version}" =~ ^${artifact_prefix_version} ]] || exit_with_error "artifact_version '${artifact_version}' does not begin with artifact_prefix_version '${artifact_prefix_version}'"
	fi

	declare -a artifact_map_debs_values=() artifact_map_packages_values=() artifact_map_debs_keys=() artifact_map_packages_keys=()

	# validate artifact_type... it must be one of the supported types
	case "${artifact_type}" in
		deb | deb-tar)
			# validate artifact_version begins with a digit
			[[ "${artifact_version}" =~ ^[0-9] ]] || exit_with_error "${artifact_type}: artifact_version '${artifact_version}' does not begin with a digit"

			# grab the the deb maps, and add them to plain arrays.
			artifact_map_debs_keys=("${!artifact_map_debs[@]}")
			artifact_map_debs_values=("${artifact_map_debs[@]}")
			artifact_map_packages_keys=("${!artifact_map_packages[@]}")
			artifact_map_packages_values=("${artifact_map_packages[@]}")

			;;
		tar.zst)
			: # valid, no restrictions on tar.zst versioning
			;;
		*)
			exit_with_error "artifact_type '${artifact_type}' is not supported"
			;;
	esac

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

		declare -a wanted_vars=(
			artifact_name
			artifact_type
			artifact_version
			artifact_version_reason
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

		exit 0
	fi

	declare -g artifact_exists_in_local_cache="undetermined"
	declare -g artifact_exists_in_remote_cache="undetermined"

	if [[ "${ARTIFACT_IGNORE_CACHE}" != "yes" ]]; then
		LOG_SECTION="artifact_is_available_in_local_cache" do_with_logging artifact_is_available_in_local_cache
		debug_var artifact_exists_in_local_cache

		# If available in local cache, we're done (except for deb-tar which needs unpacking...)
		if [[ "${artifact_exists_in_local_cache}" == "yes" ]]; then
			display_alert "artifact" "exists in local cache: ${artifact_name} ${artifact_version}" "debug"
			if [[ "${skip_unpack_if_found_in_caches:-"no"}" == "yes" ]]; then
				display_alert "artifact" "skipping unpacking as requested" "info"
			else
				LOG_SECTION="unpack_artifact_from_local_cache" do_with_logging unpack_artifact_from_local_cache
			fi

			if [[ "${ignore_local_cache:-"no"}" == "yes" ]]; then
				display_alert "artifact" "ignoring local cache as requested" "info"
			else
				display_alert "artifact" "present in local cache: ${artifact_name} ${artifact_version}" "cachehit"
				return 0
			fi
		fi

		LOG_SECTION="artifact_is_available_in_remote_cache" do_with_logging artifact_is_available_in_remote_cache
		debug_var artifact_exists_in_remote_cache

		if [[ "${artifact_exists_in_remote_cache}" == "yes" ]]; then
			display_alert "artifact" "exists in remote cache: ${artifact_name} ${artifact_version}" "debug"
			if [[ "${skip_unpack_if_found_in_caches:-"no"}" == "yes" ]]; then
				display_alert "artifact" "skipping obtain from remote & unpacking as requested" "info"
				return 0
			fi
			LOG_SECTION="artifact_obtain_from_remote_cache" do_with_logging artifact_obtain_from_remote_cache
			LOG_SECTION="unpack_artifact_from_local_cache" do_with_logging unpack_artifact_from_local_cache
			display_alert "artifact" "obtained from remote cache: ${artifact_name} ${artifact_version}" "cachehit"
			return 0
		fi
	fi

	if [[ "${artifact_exists_in_local_cache}" != "yes" && "${artifact_exists_in_remote_cache}" != "yes" ]]; then
		# Not found in any cache, so we need to build it.
		# @TODO: if deploying to remote cache, force high compression, DEB_COMPRESS="xz"
		artifact_build_from_sources # definitely will end up having its own logging sections

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
		LOG_SECTION="artifact_deploy_to_remote_cache" do_with_logging artifact_deploy_to_remote_cache
	fi
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
		run_host_command_logged tar -C "${artifact_base_dir}" -cvf "${artifact_final_file}" "${artifact_map_debs[@]}"
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

	# sanity check: after obtaining remotely, is it available locally? it should, otherwise there's some inconsistency.
	declare artifact_exists_in_local_cache="not-yet-after-obtaining-remotely"
	is_artifact_available_in_local_cache
	if [[ "${artifact_exists_in_local_cache}" == "no" ]]; then
		exit_with_error "Artifact is not available in local cache after obtaining remotely: ${artifact_full_oci_target} into '${artifact_base_dir}' file '${artifact_final_file_basename}'"
	fi

	return 0
}
