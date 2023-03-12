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

	declare -g start_timestamp # global timestamp; read below by main_default_end_build()
	start_timestamp=$(date +%s)

	### Write config summary # @TODO: or not? this is a bit useless
	LOG_SECTION="config_summary" do_with_logging write_config_summary_output_file

	# Check and install dependencies, directory structure and settings
	prepare_host # this has its own logging sections, and is possibly interactive.

	# @TODO: what if there is no python2? bookworm/sid, currently. not long until more
	# Create a directory inside WORKDIR with a "python" symlink to "/usr/bin/python2"; add it to PATH first.
	BIN_WORK_DIR="${WORKDIR}/bin"
	# No cleanup of this is necessary, since it's inside WORKDIR.
	mkdir -p "${BIN_WORK_DIR}"
	ln -s "/usr/bin/python2" "${BIN_WORK_DIR}/python"
	export PATH="${BIN_WORK_DIR}:${PATH}"

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

function main_default_end_build() {
	call_extension_method "run_after_build" <<- 'RUN_AFTER_BUILD'
		*hook for function to run after build, i.e. to change owner of `$SRC`*
		Really one of the last hooks ever called. The build has ended. Congratulations.
		- *NOTE:* this will run only if there were no errors during build process.
	RUN_AFTER_BUILD

	declare end_timestamp
	end_timestamp=$(date +%s)
	declare runtime=$(((end_timestamp - start_timestamp) / 60))
	# display_alert in its own logging section.
	LOG_SECTION="runtime_total" do_with_logging display_alert "Runtime" "${runtime} min" "info"

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
