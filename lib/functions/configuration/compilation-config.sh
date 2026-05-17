#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function prepare_compilation_vars() {
	# Only an enabled backend extension sets CCACHE, never the caller's environment.
	declare -g CCACHE=""
	call_extension_method "compile_prepare_vars" <<- 'COMPILE_PREPARE_VARS'
		*compile-cache env setup hook for ccache / sccache / similar backends*
		Called once from main_default_start_build, after all extension
		prepare_config hooks have run and before kernel/u-boot/ATF/Crust
		make invocations begin. Implementations export the env vars their
		backend needs (CCACHE, CCACHE_DIR, CCACHE_UMASK, SCCACHE_DIR, …)
		so later array-building code captures them, and tweak PATH if a
		wrapper prefix directory is needed.
	COMPILE_PREPARE_VARS

	# Framework-level limitation: USE_CCACHE / PRIVATE_CCACHE set in
	# userpatches/lib.config (sourced after initialize_extension_manager —
	# see main-config.sh:443 "too late to define hook functions or add
	# extensions in lib.config") cannot auto-enable the ccache extension.
	# Warn the user so they can migrate; we deliberately do not duplicate
	# the env-setup logic here — it lives in extensions/ccache.sh as the
	# sole owner of the ccache backend.
	if [[ ("${USE_CCACHE}" == "yes" || "${PRIVATE_CCACHE}" == "yes") && -z "${CCACHE}" ]]; then
		display_alert "USE_CCACHE / PRIVATE_CCACHE set, but no compile-cache extension is active" \
			"likely set in userpatches/lib.config (framework limit: too late to enable extensions there). Add 'ccache' to ENABLE_EXTENSIONS / EXT in your CLI, env, or config file sourced earlier." "warn"
	fi

	# moved from config: this does not belong in configuration. it's a compilation thing.
	# optimize build time with 100% CPU usage
	CPUS=$(grep -c 'processor' /proc/cpuinfo)

	# Default to 150% of CPUs to maximize compilation speed
	CTHREADS="-j$((CPUS + CPUS / 2))"

	# If CPUTHREADS is defined and a valid positive integer allow user to override CTHREADS
	# This is useful for limiting Armbian build to a specific number of threads, e.g. for build servers
	if [[ "$CPUTHREADS" =~ ^[1-9][0-9]*$ ]]; then
		CTHREADS="-j$CPUTHREADS"
		echo "Using user-defined thread count: $CTHREADS"
	fi

	call_extension_method "post_determine_cthreads" "config_post_determine_cthreads" <<- 'POST_DETERMINE_CTHREADS'
		*give config a chance modify CTHREADS programatically. A build server may work better with hyperthreads-1 for example.*
		Called early, before any compilation work starts.
	POST_DETERMINE_CTHREADS

	# readonly, global
	declare -g -r CTHREADS="${CTHREADS}"

	return 0
}
