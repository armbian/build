#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Common start/end build functions. Used by the default build and others

function main_default_start_build() {
	# 1x: show interactively-selected as soon as possible, after config
	produce_repeat_args_array
	display_alert "Repeat Build Options (early)" "${repeat_args[*]}" "ext"

	prepare_host_init # this has its own logging sections, and is possibly interactive.

	# Prepare ccache, cthreads, etc for the build
	LOG_SECTION="prepare_compilation_vars" do_with_logging prepare_compilation_vars

	# from mark_aggregation_required_in_default_build_start() possibly marked during config
	if [[ ${aggregation_required_in_default_build_start:-0} -gt 0 ]]; then
		display_alert "Configuration requires aggregation" "running aggregation now" "debug"
		aggregate_packages_in_logging_section
	else
		display_alert "Configuration does not require aggregation" "skipping aggregation" "debug"
	fi

	return 0
}

function prepare_host_init() {
	declare -g start_timestamp # global timestamp; read below by main_default_end_build()
	start_timestamp=$(date +%s)

	wait_for_disk_sync "before starting build" # fsync, wait for disk to sync, and then continue. alert user if takes too long.

	# Check that WORKDIR_BASE_TMP exists; if not, create it.
	if [[ ! -d "${WORKDIR_BASE_TMP}" ]]; then
		mkdir -p "${WORKDIR_BASE_TMP}"
	fi

	# Check the sanity of WORKDIR_BASE_TMP regarding mount options.
	LOG_SECTION="check_dir_for_mount_options" do_with_logging check_dir_for_mount_options "${WORKDIR_BASE_TMP}" "main temporary dir"

	# Starting work. Export TMPDIR, which will be picked up by all `mktemp` invocations hopefully.
	# Runner functions in logging/runners.sh will explicitly unset TMPDIR before invoking chroot.
	# Invoking chroot directly will fail in subtle ways, so, please use the runner.sh functions.
	display_alert "Starting single build, exporting TMPDIR" "${WORKDIR}" "debug"
	LOG_SECTION="prepare_tmpfs_workdir" do_with_logging prepare_tmpfs_for "WORKDIR" "${WORKDIR}" # this adds its own cleanup handler, which deletes it if it was created
	add_cleanup_handler trap_handler_cleanup_workdir                                             # this is for when it is NOT a tmpfs, for any reason; it does not delete the dir itself.

	# 'declare -g -x': global, export
	declare -g -x TMPDIR="${WORKDIR}"                    # TMPDIR is default for a lot of stuff, but...
	declare -g -x CCACHE_TEMPDIR="${WORKDIR}/ccache_tmp" # Export CCACHE_TEMPDIR, under Workdir, which is hopefully under tmpfs. Thanks @the-Going for this.
	declare -g -x XDG_RUNTIME_DIR="${WORKDIR}/xdg_tmp"   # XDG_RUNTIME_DIR is used by the likes of systemd/freedesktop centric apps.

	if [[ "${PRE_PREPARED_HOST:-"no"}" != "yes" ]]; then
		### Write config summary # @TODO: or not? this is a bit useless
		LOG_SECTION="config_summary" do_with_logging write_config_summary_output_file

		# Check and install dependencies, directory structure and settings
		prepare_host # this has its own logging sections, and is possibly interactive.
	fi

	# Create a directory inside WORKDIR with a "python" symlink to "/usr/bin/python2"; add it to PATH first.
	# -> what if there is no python2? bookworm/sid, currently. not long until more
	# ---> just try to use python3 and hope it works. it probably won't.
	BIN_WORK_DIR="${WORKDIR}/bin"
	# No cleanup of this is necessary, since it's inside WORKDIR.
	mkdir -p "${BIN_WORK_DIR}"
	if [[ -f "/usr/bin/python2" ]]; then
		display_alert "Found python2" "symlinking to ${BIN_WORK_DIR}/python" "debug"
		ln -s "/usr/bin/python2" "${BIN_WORK_DIR}/python"
	elif [[ -f "/usr/bin/python3" ]]; then
		display_alert "Found python3" "symlinking to ${BIN_WORK_DIR}/python and ${BIN_WORK_DIR}/python2" "debug"
		ln -s "/usr/bin/python3" "${BIN_WORK_DIR}/python"
		ln -s "/usr/bin/python3" "${BIN_WORK_DIR}/python2"
	else
		display_alert "No python2 or python3 found" "this is a problem" "error"
	fi
	declare -g PATH="${BIN_WORK_DIR}:${PATH}"

	return 0
}

function main_default_end_build() {
	call_extension_method "run_after_build" <<- 'RUN_AFTER_BUILD'
		*hook for function to run after build, i.e. to change owner of `$SRC`*
		Really one of the last hooks ever called. The build has ended. Congratulations.
		- *NOTE:* this will run only if there were no errors during build process.
	RUN_AFTER_BUILD

	declare end_timestamp
	end_timestamp=$(date +%s)
	declare runtime_seconds=$((end_timestamp - start_timestamp))
	# display_alert in its own logging section.
	LOG_SECTION="runtime_total" do_with_logging display_alert "Runtime" "$(printf "%d:%02d min" $((runtime_seconds / 60)) $((runtime_seconds % 60)))" "info"

	produce_repeat_args_array
	LOG_SECTION="repeat_build_options" do_with_logging display_alert "Repeat Build Options" "${repeat_args[*]}" "ext" # * = expand array, space delimited, single-word.

	return 0
}

function trap_handler_cleanup_workdir() {
	display_alert "Cleanup WORKDIR: $WORKDIR" "trap_handler_cleanup_workdir" "cleanup"
	unset TMPDIR
	if [[ -d "${WORKDIR}" ]]; then
		if [[ "${PRESERVE_WORKDIR}" != "yes" ]]; then
			if [[ "${SHOW_DEBUG}" == "yes" ]]; then
				display_alert "Cleaning up WORKDIR" "$(du -h -s "$WORKDIR")" "cleanup"
			fi
			# Remove all files and directories in WORKDIR, but not WORKDIR itself.
			rm -rf "${WORKDIR:?}"/* # Note this is protected by :?
		else
			display_alert "Preserving WORKDIR due to PRESERVE_WORKDIR=yes" "$(du -h -s "$WORKDIR")" "warn"
			# @TODO: tmpfs might just be unmounted, though.
		fi
	fi
}

function produce_repeat_args_array() {
	# Make it easy to repeat build by displaying build options used. Prepare array.
	declare -a -g repeat_args=("./compile.sh")

	# Parse ARMBIAN_HIDE_REPEAT_PARAMS which is a space separated list of parameters to hide.
	# It is created by produce_relaunch_parameters() in utils-cli.sh
	declare -a params_to_hide=()
	if [[ -n "${ARMBIAN_HIDE_REPEAT_PARAMS}" ]]; then
		IFS=' ' read -r -a params_to_hide <<< "${ARMBIAN_HIDE_REPEAT_PARAMS}"
	fi
	display_alert "Hiding parameters from repeat build options" "${params_to_hide[*]}" "debug"

	repeat_args+=("${ARMBIAN_NON_PARAM_ARGS[@]}") # Add all non-param arguments to repeat_args. This already includes any config files passed.
	declare -A repeat_params=()                   # Dict to store param values.

	for param_name in "${!ARMBIAN_PARSED_CMDLINE_PARAMS[@]}"; do # original params, but skip the hidden; those were automatically added by re-launcher
		# if param_name is in params_to_hide, skip it. Test by looping through params_to_hide.
		for param_to_hide in "${params_to_hide[@]}"; do
			if [[ "${param_name}" == "${param_to_hide}" ]]; then
				display_alert "Skipping repeat parameter" "${param_name}" "debug"
				continue 2 # continue outer (!) loop
			fi
		done

		repeat_params+=(["${param_name}"]="${ARMBIAN_PARSED_CMDLINE_PARAMS[${param_name}]}")
		display_alert "Added repeat parameter" "'${param_name}'" "debug"
	done

	for param_name in "${!ARMBIAN_INTERACTIVE_CONFIGS[@]}"; do # add params produced during interactive configuration
		repeat_params+=(["${param_name}"]="${ARMBIAN_INTERACTIVE_CONFIGS[${param_name}]}")
		display_alert "Added repeat parameter from interactive config" "'${param_name}'" "debug"
	done

	# get the sorted keys of the repeat_params associative array into an array
	declare -a repeat_params_keys_sorted=($(printf '%s\0' "${!repeat_params[@]}" | sort -z | xargs -0 -n 1 printf '%s\n'))

	for param_name in "${repeat_params_keys_sorted[@]}"; do # add sorted repeat_params to repeat_args
		declare repeat_value="${repeat_params[${param_name}]}"
		# does it contain spaces? if so, quote it.
		if [[ "${repeat_value}" =~ [[:space:]] ]]; then
			repeat_args+=("${param_name}=${repeat_value@Q}") # quote
		else
			repeat_args+=("${param_name}=${repeat_value}")
		fi
	done

	return 0
}
