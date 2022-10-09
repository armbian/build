function cli_entrypoint() {
	# array, readonly, global, for future reference, "exported" to shutup shellcheck
	declare -rg -x -a ARMBIAN_ORIGINAL_ARGV=("${@}")

	if [[ "${ARMBIAN_ENABLE_CALL_TRACING}" == "yes" ]]; then
		set -T # inherit return/debug traps
		mkdir -p "${SRC}"/output/call-traces
		echo -n "" > "${SRC}"/output/call-traces/calls.txt
		trap 'echo "${BASH_LINENO[@]}|${BASH_SOURCE[@]}|${FUNCNAME[@]}" >> ${SRC}/output/call-traces/calls.txt ;' RETURN
	fi

	# @TODO: allow for a super-early userpatches/config-000.custom.conf.sh to be loaded, before anything else.
	# This would allow for custom commands and interceptors.

	# Decide what we're gonna do. We've a few hardcoded, 1st-argument "commands".
	declare -g -A ARMBIAN_COMMANDS_TO_HANDLERS_DICT ARMBIAN_COMMANDS_TO_VARS_DICT
	armbian_register_commands # this defines the above two dictionaries

	# Process the command line, separating params (XX=YY) from non-params arguments.
	# That way they can be set in any order.
	declare -A -g ARMBIAN_PARSED_CMDLINE_PARAMS=() # A dict of PARAM=VALUE
	declare -a -g ARMBIAN_NON_PARAM_ARGS=()        # An array of all non-param arguments
	parse_cmdline_params "${@}"                    # which fills the above vars.

	# Now load the key=value pairs from cmdline into environment, before loading config or executing commands.
	# This will be done _again_ later, to make sure cmdline params override config et al.
	apply_cmdline_params_to_env "early" # which uses ARMBIAN_PARSED_CMDLINE_PARAMS
	# From here on, no more ${1} or stuff. We've parsed it all into ARMBIAN_PARSED_CMDLINE_PARAMS or ARMBIAN_NON_PARAM_ARGS and ARMBIAN_COMMAND.

	declare -a -g ARMBIAN_CONFIG_FILES=()                                            # fully validated, complete paths to config files.
	declare -g ARMBIAN_COMMAND_HANDLER="" ARMBIAN_COMMAND="" ARMBIAN_COMMAND_VARS="" # only valid command and handler will ever be set here.
	declare -g ARMBIAN_HAS_UNKNOWN_ARG="no"                                          # if any unknown params, bomb.
	for argument in "${ARMBIAN_NON_PARAM_ARGS[@]}"; do                               # loop over all non-param arguments, find commands and configs.
		parse_each_cmdline_arg_as_command_param_or_config "${argument}"                 # sets all the vars above
	done

	# More sanity checks.
	# If unknowns, bail.
	if [[ "${ARMBIAN_HAS_UNKNOWN_ARG}" == "yes" ]]; then
		exit_with_error "Unknown arguments found. Please check the output above and fix them."
	fi

	# @TODO: Have a config that is always included? "${SRC}/userpatches/config-default.conf" ?

	# If we don't have a command decided yet, use the undecided command.
	if [[ "${ARMBIAN_COMMAND}" == "" ]]; then
		display_alert "No command found, using default" "undecided" "debug"
		ARMBIAN_COMMAND="undecided"
	fi

	# If we don't have a command at this stage, we should default either to 'build' or 'docker', depending on OS.
	# Give the chosen command a chance to refuse running, or, even, change the final command to run.
	# This allows for example the 'build' command to auto-launch under docker, even without specifying it.
	# Also allows for launchers to keep themselves when re-launched, yet do something diferent. (eg: docker under docker does build).
	# Or: build under Darwin does docker...
	# each _pre_run can change the command and vars to run too, so do it in a loop until it stops changing.
	declare -g ARMBIAN_CHANGE_COMMAND_TO="${ARMBIAN_COMMAND}"
	while [[ "${ARMBIAN_CHANGE_COMMAND_TO}" != "" ]]; do
		display_alert "Still a command to pre-run, this time:" "${ARMBIAN_CHANGE_COMMAND_TO}" "debug"

		ARMBIAN_COMMAND="${ARMBIAN_CHANGE_COMMAND_TO}"
		armbian_prepare_cli_command_to_run "${ARMBIAN_COMMAND}"

		ARMBIAN_CHANGE_COMMAND_TO=""
		armbian_cli_pre_run_command
	done

	# IMPORTANT!!!: it is INVALID to relaunch compile.sh from here. It will cause logging mistakes.
	# So the last possible moment to relaunch is in xxxxx_pre_run!
	# Also form here, UUID will be generated, output created, logging enabled, etc.

	# Init basic dirs.
	declare -g DEST="${SRC}/output" USERPATCHES_PATH="${SRC}"/userpatches # DEST is the main output dir, and USERPATCHES_PATH is the userpatches dir.
	mkdir -p "${DEST}" "${USERPATCHES_PATH}"                              # Create output and userpatches directory if not already there
	display_alert "Output directory created! DEST:" "${DEST}" "debug"

	# set unique mounting directory for this execution.
	# basic deps, which include "uuidgen", will be installed _after_ this, so we gotta tolerate it not being there yet.
	declare -g ARMBIAN_BUILD_UUID
	if [[ "${ARMBIAN_BUILD_UUID}" != "" ]]; then
		display_alert "Using passed-in ARMBIAN_BUILD_UUID" "${ARMBIAN_BUILD_UUID}" "debug"
	else
		if [[ -f /usr/bin/uuidgen ]]; then
			ARMBIAN_BUILD_UUID="$(uuidgen)"
		else
			display_alert "uuidgen not found" "uuidgen not installed yet" "info"
			ARMBIAN_BUILD_UUID="no-uuidgen-yet-${RANDOM}-$((1 + $RANDOM % 10))$((1 + $RANDOM % 10))$((1 + $RANDOM % 10))$((1 + $RANDOM % 10))"
		fi
		ARMBIAN_BUILD_UUID="$(uuidgen)"
		display_alert "Generated ARMBIAN_BUILD_UUID" "${ARMBIAN_BUILD_UUID}" "debug"
	fi
	display_alert "Build UUID:" "${ARMBIAN_BUILD_UUID}" "debug"

	# Super-global variables, used everywhere. The directories are NOT _created_ here, since this very early stage.
	export WORKDIR="${SRC}/.tmp/work-${ARMBIAN_BUILD_UUID}" # WORKDIR at this stage. It will become TMPDIR later. It has special significance to `mktemp` and others!
	export LOGDIR="${SRC}/.tmp/logs-${ARMBIAN_BUILD_UUID}"  # Will be initialized very soon, literally, below.
	# @TODO: These are used by actual build, move to its cli handler.
	export SDCARD="${SRC}/.tmp/rootfs-${ARMBIAN_BUILD_UUID}"                        # SDCARD (which is NOT an sdcard, but will be, maybe, one day) is where we work the rootfs before final imaging. "rootfs" stage.
	export MOUNT="${SRC}/.tmp/mount-${ARMBIAN_BUILD_UUID}"                          # MOUNT ("mounted on the loop") is the mounted root on final image (via loop). "image" stage
	export EXTENSION_MANAGER_TMP_DIR="${SRC}/.tmp/extensions-${ARMBIAN_BUILD_UUID}" # EXTENSION_MANAGER_TMP_DIR used to store extension-composed functions
	export DESTIMG="${SRC}/.tmp/image-${ARMBIAN_BUILD_UUID}"                        # DESTIMG is where the backing image (raw, huge, sparse file) is kept (not the final destination)

	# Make sure ARMBIAN_LOG_CLI_ID is set, and unique.
	# Pre-runs might change it, but if not set, default to ARMBIAN_COMMAND.
	declare -g ARMBIAN_LOG_CLI_ID="${ARMBIAN_LOG_CLI_ID:-${ARMBIAN_COMMAND}}"

	LOG_SECTION="entrypoint" start_logging_section   # This creates LOGDIR. @TODO: also maybe causes a spurious group to be created in the log file
	add_cleanup_handler trap_handler_cleanup_logging # cleanup handler for logs; it rolls it up from LOGDIR into DEST/logs @TODO: use the COMMAND in the filenames.

	# @TODO: So gigantic contention point here about logging the basic deps installation.
	if [[ "${ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS}" == "yes" ]]; then
		if [[ "${OFFLINE_WORK}" == "yes" ]]; then
			display_alert "* " "You are working offline!"
			display_alert "* " "Sources, time and host will not be checked"
		else
			# check and install the basic utilities;
			LOG_SECTION="prepare_host_basic" do_with_logging prepare_host_basic # This includes the 'docker' case.
		fi
	fi

	# Source the extensions manager library at this point, before sourcing the config.
	# This allows early calls to enable_extension(), but initialization proper is done later.
	# shellcheck source=lib/extensions.sh
	source "${SRC}"/lib/extensions.sh

	# Loop over the ARMBIAN_CONFIG_FILES array and source each. The order is important.
	for config_file in "${ARMBIAN_CONFIG_FILES[@]}"; do
		local config_filename="${config_file##*/}" config_dir="${config_file%/*}"
		display_alert "Sourcing config file" "${config_filename}" "debug"

		# use pushd/popd to change directory to the config file's directory, so that relative paths in the config file work.
		pushd "${config_dir}" > /dev/null || exit_with_error "Failed to pushd to ${config_dir}"

		# shellcheck source=/dev/null
		LOG_SECTION="userpatches_config:${config_filename}" do_with_logging source "${config_file}"

		# reset completely after sourcing config file
		set -e
		#set -o pipefail  # trace ERR through pipes - will be enabled "soon"
		#set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable - one day will be enabled
		set -o errtrace # trace ERR through - enabled
		set -o errexit  ## set -e : exit the script if any statement returns a non-true return value - enabled

		popd > /dev/null || exit_with_error "Failed to popd from ${config_dir}"

		# Apply the params received from the command line _again_ after running the config.
		# This ensures that params take precedence over stuff possibly defined in the config.
		apply_cmdline_params_to_env "after config '${config_filename}'" # which uses ARMBIAN_PARSED_CMDLINE_PARAMS
	done

	display_alert "Executing final CLI command" "${ARMBIAN_COMMAND}" "debug"
	armbian_cli_run_command
	display_alert "Done Executing final CLI command" "${ARMBIAN_COMMAND}" "debug"

	# Build done, run the cleanup handlers explicitly.
	# This zeroes out the list of cleanups, so it"s not done again when the main script exits normally and trap = 0 runs.
	run_cleanup_handlers
}
