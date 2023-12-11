#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function prepare_compilation_vars() {
	#  moved from config: rpardini: ccache belongs in compilation, not config. I think.
	if [[ $USE_CCACHE != no ]]; then
		CCACHE=ccache
		export PATH="/usr/lib/ccache:$PATH" # this actually needs export'ing
		# private ccache directory to avoid permission issues when using build script with "sudo"
		# see https://ccache.samba.org/manual.html#_sharing_a_cache for alternative solution
		[[ $PRIVATE_CCACHE == yes ]] && export CCACHE_DIR=$SRC/cache/ccache # actual export
	else
		CCACHE=""
	fi

	# moved from config: this does not belong in configuration. it's a compilation thing.
	# optimize build time with 100% CPU usage
	CPUS=$(grep -c 'processor' /proc/cpuinfo)
	if [[ $USEALLCORES != no ]]; then
		CTHREADS="-j$((CPUS + CPUS / 2))"
	else
		CTHREADS="-j1"
	fi

	call_extension_method "post_determine_cthreads" "config_post_determine_cthreads" <<- 'POST_DETERMINE_CTHREADS'
		*give config a chance modify CTHREADS programatically. A build server may work better with hyperthreads-1 for example.*
		Called early, before any compilation work starts.
	POST_DETERMINE_CTHREADS

	# readonly, global
	declare -g -r CTHREADS="${CTHREADS}"

	return 0
}
