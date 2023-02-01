function cli_artifact_pre_run() {
	initialize_artifact "${WHAT:-"kernel"}"
	# Run the pre run adapter
	artifact_cli_adapter_pre_run
}

function cli_artifact_run() {
	display_alert "artifact" "${chosen_artifact}" "warn"
	display_alert "artifact" "${chosen_artifact} :: ${chosen_artifact_impl}()" "warn"
	artifact_cli_adapter_config_prep # only if in cli.

	# only if in cli, if not just run it bare, since we'd be already inside do_with_default_build
	do_with_default_build obtain_complete_artifact < /dev/null
}

function create_artifact_functions() {
	declare -a funcs=(
		"cli_adapter_pre_run" "cli_adapter_config_prep"
		"prepare_version"
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
						display_alert "Calling artifact function" "${impl_func}() \$*" "warn"
						${impl_func} "\$@"
					}
				ARTIFACT_DEFINITION
			)"
			eval "${cmd}"
		else
			exit_with_error "Missing artifact implementation function '${impl_func}'"
		fi
	done
}

function initialize_artifact() {
	declare -g chosen_artifact="${1}"
	armbian_register_artifacts
	declare -g chosen_artifact_impl="${ARMBIAN_ARTIFACTS_TO_HANDLERS_DICT["${chosen_artifact}"]}"
	[[ "x${chosen_artifact_impl}x" == "xx" ]] && exit_with_error "Unknown artifact '${chosen_artifact}'"
	display_alert "artifact" "${chosen_artifact} :: ${chosen_artifact_impl}()" "info"
	create_artifact_functions
}

function obtain_complete_artifact() {
	declare -g artifact_version="undetermined"
	declare -g artifact_version_reason="undetermined"
	declare -A -g artifact_map_versions=()
	declare -A -g artifact_map_versions_legacy=()

	# Check if REVISION is set, otherwise exit_with_error
	[[ "x${REVISION}x" == "xx" ]] && exit_with_error "REVISION is not set"

	artifact_prepare_version
	debug_var artifact_version
	debug_var artifact_version_reason
	debug_dict artifact_map_versions_legacy
	debug_dict artifact_map_versions

	# @TODO the whole artifact upload/download dance
	artifact_is_available_in_local_cache
	artifact_is_available_in_remote_cache
	artifact_obtain_from_remote_cache

	artifact_build_from_sources

	artifact_deploy_to_remote_cache
}

# This is meant to be run after config, inside default build.
function build_artifact() {
	initialize_artifact "${WHAT:-"kernel"}"
	obtain_complete_artifact
}

function capture_rename_legacy_debs_into_artifacts() {
	LOG_SECTION="capture_rename_legacy_debs_into_artifacts" do_with_logging capture_rename_legacy_debs_into_artifacts_logged
}

function capture_rename_legacy_debs_into_artifacts_logged() {
	# So the deb-building code will consider the artifact_version in it's "Version: " field in the .debs.
	# But it will produce .deb's with the legacy name. We gotta find and rename them.
	# Loop over the artifact_map_versions, and rename the .debs.
	debug_dict artifact_map_versions_legacy
	debug_dict artifact_map_versions

	declare deb_name_base deb_name_full new_name_full legacy_version legacy_base_version
	for deb_name_base in "${!artifact_map_versions[@]}"; do
		legacy_base_version="${artifact_map_versions_legacy[${deb_name_base}]}"
		if [[ -z "${legacy_base_version}" ]]; then
			exit_with_error "Legacy base version not found for artifact '${deb_name_base}'"
		fi

		display_alert "Legacy base version" "${legacy_base_version}" "info"
		legacy_version="${legacy_base_version}_${ARCH}" # Arch-specific package; has ARCH at the end.
		deb_name_full="${DEST}/debs/${deb_name_base}_${legacy_version}.deb"
		new_name_full="${DEST}/debs/${deb_name_base}_${artifact_map_versions[${deb_name_base}]}_${ARCH}.deb"
		display_alert "Full legacy deb name" "${deb_name_full}" "info"
		display_alert "New artifact deb name" "${new_name_full}" "info"
		run_host_command_logged mv -v "${deb_name_full}" "${new_name_full}"
	done
}
