#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# Runs a compile command between the compile_wrapper_pre and compile_wrapper_post
# extension hooks; without implementations the command runs unchanged.
function do_with_compile_wrapper() {
	# Registered before the pre hooks, so a failing pre hook or an interrupt still runs the post hooks.
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

	# Run the post hooks now, whatever the exit code, and not again at script exit.
	execute_and_remove_cleanup_handler _do_with_compile_wrapper_run_post

	return ${build_exit_code}
}

function _do_with_compile_wrapper_run_post() {
	call_extension_method "compile_wrapper_post" <<- 'COMPILE_WRAPPER_POST'
		*post-compilation hook for cache wrappers and similar*
		Called once after the wrapped compilation command completes (success
		or failure) or is interrupted. Implementations may display stats,
		flush a remote cache write buffer, shut down a helper server, etc.
	COMPILE_WRAPPER_POST
}
