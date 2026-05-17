#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#
# Compile-cache backend: ccache (https://ccache.dev/).
#
# Wraps compiler invocations for kernel / u-boot / ATF / Crust through the
# `ccache` binary and emits per-build hit/miss stats. Implements the generic
# `compile_prepare_vars` (env exports) and `compile_wrapper_pre/post` hooks
# (stats, also fired on interrupt). Per-artifact `*_make_config` hooks
# inject CCACHE_UMASK into the env-i make envs since the kernel/u-boot
# auto-passthrough only covers CCACHE_DIR.
#
# Auto-enabled by core when USE_CCACHE=yes / PRIVATE_CCACHE=yes is set, or
# when the ccache-remote extension is requested (see
# main_config_redefine_user_target in main-config.sh). Can also be enabled
# explicitly via ENABLE_EXTENSIONS=ccache regardless of the USE_CCACHE
# toggle.
#
# Mutually exclusive with other compile-cache extensions (sccache, …) — the
# mutex is enforced in extension_prepare_config__ccache.
#
# Ordering invariant: env wiring lives in compile_prepare_vars__ccache,
# which fires from prepare_compilation_vars (start-end.sh) — late
# enough that every extension_prepare_config_* and the userpatches /
# user_config phases have settled values like PRIVATE_CCACHE, and early
# enough that ${CCACHE} substitution and PATH prefix propagate into the
# arrays built by run_*_make_internal. Order is fixed by core, not by
# alphabetical hook name resolution.

# SHOW_CCACHE state shared by the pre and post hooks.
declare -g __ext_ccache_dir_actual=""
declare -g __ext_ccache_dir_size_before=""

# Mutually-exclusive list of compile-cache extensions. Update when a new
# backend extension is added (sccache, …).
declare -g -a __ext_ccache_conflicting_exts=("sccache")

function extension_prepare_config__ccache() {
	# Use the shared normalization (EXT fallback + comma/whitespace handling).
	local _ext_list other
	_ext_list="$(extension_list_normalized)"
	for other in "${__ext_ccache_conflicting_exts[@]}"; do
		if [[ "${_ext_list}" == *",${other},"* ]]; then
			exit_with_error "${EXTENSION}: 'ccache' and '${other}' extensions are mutually exclusive — choose one compile-cache backend"
		fi
	done
	# All env setup lives in compile_prepare_vars__ccache (called from
	# prepare_compilation_vars). See ordering invariant in the file header.
}

# Main env setup. Runs from prepare_compilation_vars — late enough that
# values set by other extensions (PRIVATE_CCACHE from ccache-remote) and
# by userpatches/lib.config / user_config hooks are settled, and early
# enough that ${CCACHE} substitution in run_*_make_internal sees the
# exported value.
function compile_prepare_vars__ccache() {
	# Make the binary substitution available wherever scripts reference
	# ${CCACHE} (kernel-make.sh, uboot.sh, atf.sh, crust.sh).
	export CCACHE="ccache"

	# Drop a wrapper directory in front of PATH so bare `gcc` invocations
	# also route through ccache via /usr/lib/ccache symlinks. This becomes
	# part of the PATH captured by kernel-make.sh and uboot.sh when they
	# build the env-i make environment.
	export PATH="/usr/lib/ccache:${PATH}"

	# private ccache dir avoids permission issues when build is run as root
	# while user invokes via sudo; see https://ccache.samba.org/manual.html#_sharing_a_cache
	if [[ "${PRIVATE_CCACHE}" == "yes" && -z "${CCACHE_DIR}" ]]; then
		export CCACHE_DIR="${SRC}/cache/ccache"
	elif [[ -n "${CCACHE_DIR}" ]]; then
		# CCACHE_DIR set by user or another extension: make sure it is exported.
		export CCACHE_DIR
	fi

	# A shared cache is world-writable so several users on one host can use it.
	if [[ -z "${CCACHE_UMASK}" && "${PRIVATE_CCACHE}" != "yes" ]]; then
		export CCACHE_UMASK=000
	elif [[ -n "${CCACHE_UMASK}" ]]; then
		export CCACHE_UMASK
	fi
}

# Kernel and u-boot make run under env -i; core passes CCACHE_DIR there, we add CCACHE_UMASK.
function _ext_ccache_inject_umask() {
	local -n envs="$1"
	[[ -n "${CCACHE_UMASK}" ]] && envs+=("CCACHE_UMASK=${CCACHE_UMASK@Q}")
	return 0
}

function kernel_make_config__ccache() { _ext_ccache_inject_umask common_make_envs; }
function uboot_make_config__ccache() { _ext_ccache_inject_umask uboot_make_envs; }
# ATF and Crust make run without env -i and inherit the exported CCACHE_UMASK.

function compile_wrapper_pre__ccache() {
	display_alert "Clearing ccache statistics" "ccache" "ccache"
	run_host_command_logged ccache --zero-stats

	if [[ "${SHOW_CCACHE}" == "yes" ]]; then
		display_alert "CCACHE_DIR" "${CCACHE_DIR:-"unset"}" "ccache"
		display_alert "CCACHE_TEMPDIR" "${CCACHE_TEMPDIR:-"unset"}" "ccache"

		__ext_ccache_dir_actual="$(ccache --show-config | grep "cache_dir =" | cut -d "=" -f 2 | xargs echo)"

		# cache_dir may be unreported or not yet created; `du` on it would fail under set -e.
		local ccache_dir_size_before_human
		if [[ -n "${__ext_ccache_dir_actual}" && -d "${__ext_ccache_dir_actual}" ]]; then
			__ext_ccache_dir_size_before="$(du -sb "${__ext_ccache_dir_actual}" | cut -f 1)"
			ccache_dir_size_before_human="$(numfmt --to=iec-i --suffix=B --format="%.2f" "${__ext_ccache_dir_size_before}")"
			display_alert "ccache dir size before" "${ccache_dir_size_before_human}" "ccache"
		else
			__ext_ccache_dir_size_before="0"
			display_alert "ccache dir size before" "unavailable (cache dir not resolved)" "wrn"
		fi

		wait_for_disk_sync "before ccache config"
		display_alert "ccache configuration" "ccache" "ccache"
		run_host_command_logged ccache --show-config "&&" sync
	fi

	display_alert "Running ccache'd build..." "ccache" "ccache"
}

function compile_wrapper_post__ccache() {
	local stats_output direct_hit direct_miss pct
	stats_output=$(ccache --print-stats 2>&1 || true)
	direct_hit=$(ccache_get_stat "${stats_output}" "direct_cache_hit")
	direct_miss=$(ccache_get_stat "${stats_output}" "direct_cache_miss")
	pct=$(ccache_hit_pct "${direct_hit}" "${direct_miss}")
	display_alert "Ccache result" "hit=${direct_hit} miss=${direct_miss} (${pct}%)" "info"

	# Hook for extensions to show additional stats (e.g., remote storage)
	call_extension_method "ccache_post_compilation" <<- 'CCACHE_POST_COMPILATION'
		*called after ccache-wrapped compilation completes (success or failure)*
		Useful for displaying remote cache statistics or other post-build info.
	CCACHE_POST_COMPILATION

	if [[ "${SHOW_CCACHE}" == "yes" ]]; then
		display_alert "Display ccache statistics" "ccache" "ccache"
		run_host_command_logged ccache --show-stats --verbose

		# Mirror the pre-hook guard: skip diff if we never resolved the dir.
		if [[ -n "${__ext_ccache_dir_actual}" && -d "${__ext_ccache_dir_actual}" ]]; then
			local ccache_dir_size_after ccache_dir_size_diff ccache_dir_size_diff_human
			ccache_dir_size_after="$(du -sb "${__ext_ccache_dir_actual}" | cut -f 1)"
			ccache_dir_size_diff="$((ccache_dir_size_after - __ext_ccache_dir_size_before))"
			ccache_dir_size_diff_human="$(numfmt --to=iec-i --suffix=B --format="%.2f" -- "${ccache_dir_size_diff}")"
			display_alert "ccache dir size change" "${ccache_dir_size_diff_human}" "ccache"
		else
			display_alert "ccache dir size change" "unavailable (cache dir not resolved)" "wrn"
		fi
	fi
}

# Parse a single numeric field from "ccache --print-stats" tab-separated output
# Returns 0 if field not found or not numeric
function ccache_get_stat() {
	local stats_output="$1" field="$2"
	local val
	val=$(echo "${stats_output}" | grep "^${field}" | cut -f2 || true)
	[[ "${val}" =~ ^[0-9]+$ ]] || val=0
	echo "${val}"
}

# Calculate hit percentage from hit and miss counts
function ccache_hit_pct() {
	local hit="$1" miss="$2"
	local total=$((hit + miss))
	if [[ ${total} -gt 0 ]]; then
		echo $((hit * 100 / total))
	else
		echo 0
	fi
}
