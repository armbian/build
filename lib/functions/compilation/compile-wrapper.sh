#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Generic compile-time wrapper, backend-agnostic.
#
# Wraps a compilation command (`make ...` invocation in run_host_command_logged
# or similar) with two extension hooks:
#
#   compile_wrapper_pre   — called before the build. Extensions zero stats,
#                           start long-lived helper servers, assert backend
#                           health, etc.
#   compile_wrapper_post  — called after the build (also on SIGINT/errexit via
#                           the registered cleanup handler). Extensions show
#                           stats, push final cache batches, etc.
#
# Extensions are identified by the conventional double-underscore suffix:
#     compile_wrapper_pre__<extension_name>()
#     compile_wrapper_post__<extension_name>()
#
# Default behavior with no extensions registered: passthrough — the command
# runs unchanged. This makes the wrapper safe to drop in everywhere a
# compilation invocation lives, without committing to any specific cache
# backend.
function do_with_compile_wrapper() {
	# Register the post-hook as a cleanup handler BEFORE running pre hooks.
	# A compile_wrapper_pre implementation may start a long-lived helper
	# (e.g. `sccache --start-server`); if another pre hook then fails or the
	# user interrupts during pre-hook execution, the post hook must still
	# fire so backend cleanup (stop helpers, flush state) is not skipped.
	add_cleanup_handler _do_with_compile_wrapper_run_post

	call_extension_method "compile_wrapper_pre" <<- 'COMPILE_WRAPPER_PRE'
		*pre-compilation hook for cache wrappers (ccache, sccache, …) and
		similar backend-agnostic setup*
		Called once right before the wrapped compilation command runs.
		Implementations may zero stats counters, start a long-lived helper
		process, validate that a remote backend is reachable, etc.
		The matching compile_wrapper_post hook is guaranteed to fire even
		if a later pre hook fails or the build is interrupted, so cleanup
		of resources started here is safe to rely on.
	COMPILE_WRAPPER_PRE

	local build_exit_code=0
	"$@" || build_exit_code=$?

	# Remove and explicitly run the post-hook on the success path so it does
	# not also fire from the cleanup handler at script exit.
	execute_and_remove_cleanup_handler _do_with_compile_wrapper_run_post

	return ${build_exit_code}
}

# Internal — invoked by do_with_compile_wrapper either directly on success or
# via the cleanup-handler chain on interruption. Kept as a separate function
# so it has a stable name to register with add_cleanup_handler.
function _do_with_compile_wrapper_run_post() {
	call_extension_method "compile_wrapper_post" <<- 'COMPILE_WRAPPER_POST'
		*post-compilation hook for cache wrappers and similar*
		Called once after the wrapped compilation command completes (success
		or failure) or is interrupted. Implementations may display stats,
		flush a remote cache write buffer, shut down a helper server, etc.
	COMPILE_WRAPPER_POST
}
