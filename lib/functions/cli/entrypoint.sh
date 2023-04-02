#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function cli_entrypoint() {
	# array, readonly, global, for future reference, "exported" to shutup shellcheck
	declare -rg -x -a ARMBIAN_ORIGINAL_ARGV=("${@}")

	if [[ "${ARMBIAN_ENABLE_CALL_TRACING}" == "yes" ]]; then
		set -T # inherit return/debug traps
		mkdir -p "${SRC}"/output/call-traces
		echo -n "" > "${SRC}"/output/call-traces/calls.txt
		# See https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html
		trap 'echo "${FUNCNAME[*]}|${BASH_LINENO[*]}|${BASH_SOURCE[*]}|${LINENO}" >> ${SRC}/output/call-traces/calls.txt ;' RETURN
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

	# Re-initialize logging, to take into account the new environment after parsing cmdline params.
	logging_init

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

		declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="no" # reset this before every pre_run, so only the last one wins.
		ARMBIAN_COMMAND="${ARMBIAN_CHANGE_COMMAND_TO}"
		armbian_prepare_cli_command_to_run "${ARMBIAN_COMMAND}"

		ARMBIAN_CHANGE_COMMAND_TO=""
		armbian_cli_pre_run_command
	done

	# IMPORTANT!!!: it is INVALID to relaunch compile.sh from here. It will cause logging mistakes.
	# So the last possible moment to relaunch is in xxxxx_pre_run!
	# Also form here, UUID will be generated, output created, logging enabled, etc.

	# Init basic dirs.
	declare -g -r DEST="${SRC}/output" USERPATCHES_PATH="${SRC}"/userpatches # DEST is the main output dir, and USERPATCHES_PATH is the userpatches dir. read-only.
	mkdir -p "${DEST}" "${USERPATCHES_PATH}"                                 # Create output and userpatches directory if not already there
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
		display_alert "Generated ARMBIAN_BUILD_UUID" "${ARMBIAN_BUILD_UUID}" "debug"
	fi
	declare -g -r ARMBIAN_BUILD_UUID="${ARMBIAN_BUILD_UUID}" # Make read-only
	display_alert "Build UUID:" "${ARMBIAN_BUILD_UUID}" "debug"

	# Super-global variables, used everywhere. The directories are NOT _created_ here, since this very early stage. They are all readonly, for sanity.
	declare -g -r WORKDIR_BASE_TMP="${SRC}/.tmp" # a.k.a. ".tmp" dir. it is a shared base dir for all builds, but each build gets its own WORKDIR/TMPDIR.

	declare -g -r WORKDIR="${WORKDIR_BASE_TMP}/work-${ARMBIAN_BUILD_UUID}"                         # WORKDIR at this stage. It will become TMPDIR later. It has special significance to `mktemp` and others!
	declare -g -r LOGDIR="${WORKDIR_BASE_TMP}/logs-${ARMBIAN_BUILD_UUID}"                          # Will be initialized very soon, literally, below.
	declare -g -r EXTENSION_MANAGER_TMP_DIR="${WORKDIR_BASE_TMP}/extensions-${ARMBIAN_BUILD_UUID}" # EXTENSION_MANAGER_TMP_DIR used to store extension-composed functions

	# @TODO: These are used only by rootfs/image actual build, move there...
	declare -g -r SDCARD="${WORKDIR_BASE_TMP}/rootfs-${ARMBIAN_BUILD_UUID}" # SDCARD (which is NOT an sdcard, but will be, maybe, one day) is where we work the rootfs before final imaging. "rootfs" stage.
	declare -g -r MOUNT="${WORKDIR_BASE_TMP}/mount-${ARMBIAN_BUILD_UUID}"   # MOUNT ("mounted on the loop") is the mounted root on final image (via loop). "image" stage
	declare -g -r DESTIMG="${WORKDIR_BASE_TMP}/image-${ARMBIAN_BUILD_UUID}" # DESTIMG is where the backing image (raw, huge, sparse file) is kept (not the final destination)

	# Make sure ARMBIAN_LOG_CLI_ID is set, and unique, and readonly.
	# Pre-runs might change it before this, but if not set, default to ARMBIAN_COMMAND.
	declare -r -g ARMBIAN_LOG_CLI_ID="${ARMBIAN_LOG_CLI_ID:-${ARMBIAN_COMMAND}}"

	# If we're on Linux & root, mount tmpfs on LOGDIR. This has it's own cleanup handler.
	# It also _creates_ the LOGDIR, and the cleanup handler will delete.
	prepare_tmpfs_for "LOGDIR" "${LOGDIR}"

	LOG_SECTION="entrypoint" start_logging_section      # This will create LOGDIR if it does not exist. @TODO: also maybe causes a spurious group to be created in the log file
	add_cleanup_handler trap_handler_cleanup_logging    # cleanup handler for logs; it rolls it up from LOGDIR into DEST/logs
	add_cleanup_handler trap_handler_reset_output_owner # make sure output folder is owned by pre-sudo/pre-Docker user if that's the case

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

	# Legacy. We used to source the extension manager here, but now it's included in the library.
	# @TODO: a quick check on the globals in extensions.sh would get rid of this.
	extension_manager_declare_globals

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

	# Early check for deprecations
	error_if_lib_tag_set # make sure users are not thrown off by using old parameter which does nothing anymore; explain

	display_alert "Executing final CLI command" "${ARMBIAN_COMMAND}" "debug"
	armbian_cli_run_command
	display_alert "Done Executing final CLI command" "${ARMBIAN_COMMAND}" "debug"

	# Build done, run the cleanup handlers explicitly.
	# This zeroes out the list of cleanups, so it"s not done again when the main script exits normally and trap = 0 runs.
	run_cleanup_handlers
}
