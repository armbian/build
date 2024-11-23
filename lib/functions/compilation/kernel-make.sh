#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
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
		"CCACHE_BASEDIR=\"$(pwd)\""                                   # Base directory for ccache, for cache reuse # @TODO: experiment with this and the source path to maximize hit rate
		"CCACHE_TEMPDIR=\"${CCACHE_TEMPDIR:?}\""                      # Temporary directory for ccache, under WORKDIR
		"PATH=\"${toolchain}:${PYTHON3_INFO[USERBASE]}/bin:${PATH}\"" # Insert the toolchain and the pip binaries into the PATH
		"PYTHONPATH=\"${PYTHON3_INFO[MODULES_PATH]}:${PYTHONPATH}\""  # Insert the pip modules downloaded by Armbian into PYTHONPATH (needed for dtb checks)
		"DPKG_COLORS=always"                                          # Use colors for dpkg @TODO no dpkg is done anymore, remove?
		"XZ_OPT='--threads=0'"                                        # Use parallel XZ compression
		"TERM='${TERM}'"                                              # Pass the terminal type, so that 'make menuconfig' can work.
		"COLUMNS='${COLUMNS:-160}'"
		"COLORFGBG='${COLORFGBG}'"
	)

	# If CCACHE_DIR is set, pass it to the kernel build; Pass the ccache dir explicitly, since we'll run under "env -i"
	if [[ -n "${CCACHE_DIR}" ]]; then
		common_make_envs+=("CCACHE_DIR='${CCACHE_DIR}'")
	fi

	# Add the distcc envs, if any.
	common_make_envs+=("${DISTCC_EXTRA_ENVS[@]}")

	if [[ "${KERNEL_COMPILER}" == "clang" ]]; then
		llvm_flag="LLVM=1"
		cc_name="CC"
		extra_warnings="-Wno-error=unused-command-line-argument -Wno-error=unknown-warning-option" # downgrade errors to warnings
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

	# last statement, so it passes the result to calling function. "env -i" is used for empty env
	full_command=("${KERNEL_MAKE_RUNNER:-run_host_command_logged}" "env" "-i" "${common_make_envs[@]}"
		make "${common_make_params_quoted[@]@Q}" "$@" "${make_filter}")
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
	# if it matches we use the system compiler
	if dpkg-architecture -e "${ARCH}"; then
		display_alert "Native compilation" "target ${ARCH} on host $(dpkg --print-architecture)"
	else
		display_alert "Cross compilation" "target ${ARCH} on host $(dpkg --print-architecture)"
		toolchain=$(find_toolchain "$KERNEL_COMPILER" "$KERNEL_USE_GCC")
		[[ -z $toolchain ]] && exit_with_error "Could not find required toolchain" "${KERNEL_COMPILER}gcc $KERNEL_USE_GCC"
	fi

	if [[ "${KERNEL_COMPILER}" == "clang" ]]; then
		KERNEL_COMPILER_FULL="${KERNEL_COMPILER}"
	else
		KERNEL_COMPILER_FULL="${KERNEL_COMPILER}gcc"
	fi
	kernel_compiler_version="$(eval env PATH="${toolchain}:${PATH}" "${KERNEL_COMPILER_FULL}" -dumpfullversion -dumpversion)"
	display_alert "Compiler version" "${KERNEL_COMPILER_FULL} ${kernel_compiler_version}" "info"
}
