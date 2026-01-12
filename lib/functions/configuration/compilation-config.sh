#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function prepare_compilation_vars() {
	#  moved from config: rpardini: ccache belongs in compilation, not config. I think.
	if [[ $USE_CCACHE == yes || ${PRIVATE_CCACHE} == yes ]]; then
		display_alert "using CCACHE" "USE_CCACHE or PRIVATE_CCACHE is set to yes" "warn"

		CCACHE=ccache
		export PATH="/usr/lib/ccache:$PATH" # this actually needs export'ing
		# private ccache directory to avoid permission issues when using build script with "sudo"
		# see https://ccache.samba.org/manual.html#_sharing_a_cache for alternative solution
		[[ $PRIVATE_CCACHE == yes ]] && export CCACHE_DIR=$SRC/cache/ccache # actual export

		# Set default umask for ccache to allow write access for all users (enables cache sharing)
		# CCACHE_UMASK=000 creates files with permissions 666 (rw-rw-rw-) and dirs with 777 (rwxrwxrwx)
		# Only set this for shared cache, not for private cache
		[[ -z "${CCACHE_UMASK}" && "${PRIVATE_CCACHE}" != "yes" ]] && export CCACHE_UMASK=000
	else
		CCACHE=""
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
