#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function run_kernel_make_internal() {
	set -e
	declare -a common_make_params_quoted common_make_envs full_command

	# Prepare distcc, if enabled.
	declare -a -g DISTCC_EXTRA_ENVS=()
	declare -a -g DISTCC_CROSS_COMPILE_PREFIX=()
	declare -a -g DISTCC_MAKE_J_PARALLEL=()
	prepare_distcc_compilation_config

	common_make_envs=(
		"CCACHE_BASEDIR='$(pwd)'"                                  # Base directory for ccache, for cache reuse # @TODO: experiment with this and the source path to maximize hit rate
		"CCACHE_TEMPDIR='${CCACHE_TEMPDIR:?}'"                     # Temporary directory for ccache, under WORKDIR
		"PATH='${PYTHON3_INFO[USERBASE]}/bin:${PATH}'"             # Insert the pip binaries into the PATH
		"PYTHONPATH='${PYTHON3_INFO[MODULES_PATH]}:${PYTHONPATH}'" # Insert the pip modules downloaded by Armbian into PYTHONPATH (needed for dtb checks)
		"DPKG_COLORS=always"                                       # Use colors for dpkg @TODO no dpkg is done anymore, remove?
		"XZ_OPT='--threads=0'"                                     # Use parallel XZ compression
		"TERM='${TERM}'"                                           # Pass the terminal type, so that 'make menuconfig' can work.
		"COLUMNS='${COLUMNS:-160}'"
		"COLORFGBG='${COLORFGBG}'"
	)

	# If CCACHE_DIR is set, pass it to the kernel build; Pass the ccache dir explicitly, since we'll run under "env -i"
	if [[ -n "${CCACHE_DIR}" ]]; then
		common_make_envs+=("CCACHE_DIR=${CCACHE_DIR@Q}")
	fi

	# Add the distcc envs, if any.
	common_make_envs+=("${DISTCC_EXTRA_ENVS[@]}")

	if [[ "${KERNEL_COMPILER}" == "clang" ]]; then
		llvm_flag="LLVM=1"
		cc_name="CC"
		# Only suppress unused-command-line-argument errors
		# Do NOT add -Wno-error=unknown-warning-option here - it breaks cc-option detection
		# in kernel Makefiles (btrfs, drm, coresight) causing GCC-specific flags to be
		# incorrectly added when building with clang
		extra_warnings="-fcolor-diagnostics -Wno-error=unused-command-line-argument"
	else
		cc_name="CROSS_COMPILE"
		extra_warnings=""
	fi
	common_make_params_quoted=(
		# @TODO: introduce O=path/to/binaries, so sources and bins are not in the same dir; this has high impact in headers packaging though.

		"${DISTCC_MAKE_J_PARALLEL[@]}" # Parallel compile, "-j X" for X cpus; determined by distcc, or is just "$CTHREADS" if distcc is not enabled.

		"ARCH=${ARCHITECTURE}"                   # Key param. Everything depends on this.
		"LOCALVERSION=-${BRANCH}-${LINUXFAMILY}" # Change the internal kernel version to include the family. Changing this causes recompiles # @TODO change hack at .config; that might handles mtime better

		"${cc_name}=${CCACHE} ${DISTCC_CROSS_COMPILE_PREFIX[@]} ${KERNEL_COMPILER}"                                         # added as prefix to every compiler invocation by make
		"KCFLAGS=-fdiagnostics-color=always -Wno-error=misleading-indentation ${extra_warnings} ${KERNEL_EXTRA_CFLAGS:-""}" # Force GCC colored messages, downgrade misleading indentation to warning

		"SOURCE_DATE_EPOCH=${kernel_base_revision_ts}"        # https://reproducible-builds.org/docs/source-date-epoch/ and https://www.kernel.org/doc/html/latest/kbuild/reproducible-builds.html
		"KBUILD_BUILD_TIMESTAMP=${kernel_base_revision_date}" # https://www.kernel.org/doc/html/latest/kbuild/kbuild.html#kbuild-build-timestamp
		"KBUILD_BUILD_USER=build"                             # https://www.kernel.org/doc/html/latest/kbuild/kbuild.html#kbuild-build-user-kbuild-build-host
		"KBUILD_BUILD_HOST=armbian"                           # https://www.kernel.org/doc/html/latest/kbuild/kbuild.html#kbuild-build-user-kbuild-build-host

		# Parallel compression, use explicit parallel compressors https://lore.kernel.org/lkml/20200901151002.988547791@linuxfoundation.org/
		"KGZIP=pigz"
		"KBZIP2=pbzip2"
		# Parallel compression for `xz` if needed can be added with "XZ_OPT=\"--threads=0\""
	)
	if [[ -n "${llvm_flag}" ]]; then
		common_make_params_quoted+=("${llvm_flag}")
	fi

	# Hook order: kernel_make_config runs first (generic extension config),
	# then custom_kernel_make_params (user/board overrides can take precedence).
	call_extension_method "kernel_make_config" <<- 'KERNEL_MAKE_CONFIG'
		*Hook to customize kernel make environment and parameters*
		Called right before invoking make for kernel compilation.
		Available arrays to modify:
		  - common_make_envs[@]: environment variables passed via "env -i" (e.g., CCACHE_REMOTE_STORAGE)
		  - common_make_params_quoted[@]: make command parameters (e.g., custom flags)
		Available read-only variables:
		  - KERNEL_COMPILER, ARCHITECTURE, BRANCH, LINUXFAMILY
	KERNEL_MAKE_CONFIG

	# Runs after kernel_make_config — allows user/board overrides to take precedence
	call_extension_method "custom_kernel_make_params" <<- 'CUSTOM_KERNEL_MAKE_PARAMS'
		*Customize kernel make parameters before compilation*
		Called after all standard make parameters are set but before invoking make.
		Extensions can modify the following arrays:
		- `common_make_params_quoted` - parameters passed to make (e.g., CROSS_COMPILE_COMPAT)
		- `common_make_envs` - environment variables for make
	CUSTOM_KERNEL_MAKE_PARAMS

	# last statement, so it passes the result to calling function. "env -i" is used for empty env
	full_command=("${KERNEL_MAKE_RUNNER:-run_host_command_logged}" "env" "-i" "${common_make_envs[@]}"
		make "${common_make_params_quoted[@]@Q}" "$@")
	"${full_command[@]}" # and exit with it's code, since it's the last statement
}

function run_kernel_make() {
	KERNEL_MAKE_RUNNER="run_host_command_logged" KERNEL_MAKE_UNBUFFER="unbuffer" run_kernel_make_internal "$@"
}

function run_kernel_make_dialog() {
	KERNEL_MAKE_RUNNER="run_host_command_dialog" run_kernel_make_internal "$@"
}

function run_kernel_make_long_running() {
	local seconds_start=${SECONDS} # Bash has a builtin SECONDS that is seconds since start of script
	KERNEL_MAKE_UNBUFFER="unbuffer" run_kernel_make_internal "$@"
	display_alert "Kernel Make '$*' took" "$((SECONDS - seconds_start)) seconds" "debug"
}

function kernel_determine_toolchain() {
	# compare with the architecture of the current Debian node
	if dpkg-architecture -e "${ARCH}"; then
		display_alert "Native compilation" "target ${ARCH} on host $(dpkg --print-architecture)"
	else
		display_alert "Cross compilation" "target ${ARCH} on host $(dpkg --print-architecture)"
	fi

	declare kernel_compiler_full kernel_compiler_version
	if [[ "${KERNEL_COMPILER}" == "clang" ]]; then
		kernel_compiler_full="${KERNEL_COMPILER}"
	else
		kernel_compiler_full="${KERNEL_COMPILER}gcc"
	fi
	kernel_compiler_version="$(eval env "${kernel_compiler_full}" -dumpfullversion -dumpversion)"
	display_alert "Compiler version" "${kernel_compiler_full} ${kernel_compiler_version}" "info"
}
