function cli_artifact_pre_run() {
	armbian_register_artifacts
	declare -g chosen_artifact="${WHAT:-"kernel"}"
	declare -g chosen_artifact_impl="${ARMBIAN_ARTIFACTS_TO_HANDLERS_DICT["${chosen_artifact}"]}"
	[[ "x${chosen_artifact_impl}x" == "xx" ]] && exit_with_error "Unknown artifact '${chosen_artifact}'"
	display_alert "artifact" "${chosen_artifact} :: ${chosen_artifact_impl}()" "info"

	create_artifact_functions

	# Run the pre run adapter
	artifact_cli_adapter_pre_run
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
		#display_alert "artifact" "looking for function '${impl_func}'" "info"
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
			#display_alert "Creating artifact function" "${func}()" "info"
			#display_alert "Creating artifact function" "${cmd}" "info"
			eval "${cmd}"
		else
			exit_with_error "Missing artifact implementation function '${impl_func}'"
		fi
	done
}

function cli_artifact_run() {
	display_alert "artifact" "${chosen_artifact}" "warn"
	display_alert "artifact" "${chosen_artifact} :: ${chosen_artifact_impl}()" "warn"
	artifact_cli_adapter_config_prep # only if in cli.

	function obtain_complete_artifact() {
		declare artifact_version="undetermined"
		artifact_prepare_version
		debug_var artifact_version
		debug_var artifact_version_reason
		
		
		artifact_is_available_in_local_cache
		artifact_is_available_in_remote_cache
		artifact_obtain_from_remote_cache
		artifact_build_from_sources
		artifact_deploy_to_remote_cache
	}
	# only if in cli, if not just run it bare, since we'd be already inside do_with_default_build
	do_with_default_build obtain_complete_artifact < /dev/null
}
