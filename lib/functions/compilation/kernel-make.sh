#!/usr/bin/env bash

function run_kernel_make_internal() {
	set -e
	declare -a common_make_params_quoted common_make_envs full_command

	# Prepare distcc, if enabled.
	declare -a -g DISTCC_EXTRA_ENVS=()
	declare -a -g DISTCC_CROSS_COMPILE_PREFIX=()
	declare -a -g DISTCC_MAKE_J_PARALLEL=()
	prepare_distcc_compilation_config

	common_make_envs=(
		"CCACHE_BASEDIR=\"$(pwd)\""              # Base directory for ccache, for cache reuse # @TODO: experiment with this and the source path to maximize hit rate
		"CCACHE_TEMPDIR=\"${CCACHE_TEMPDIR:?}\"" # Temporary directory for ccache, under WORKDIR
		"PATH=\"${toolchain}:${PATH}\""          # Insert the toolchain first into the PATH.
		"DPKG_COLORS=always"                     # Use colors for dpkg @TODO no dpkg is done anymore, remove?
		"XZ_OPT='--threads=0'"                   # Use parallel XZ compression
		"TERM='${TERM}'"                         # Pass the terminal type, so that 'make menuconfig' can work.
	)

	# If CCACHE_DIR is set, pass it to the kernel build; Pass the ccache dir explicitly, since we'll run under "env -i"
	if [[ -n "${CCACHE_DIR}" ]]; then
		common_make_envs+=("CCACHE_DIR='${CCACHE_DIR}'")
	fi

	# Add the distcc envs, if any.
	common_make_envs+=("${DISTCC_EXTRA_ENVS[@]}")

	common_make_params_quoted=(
		# @TODO: introduce O=path/to/binaries, so sources and bins are not in the same dir; this has high impact in headers packaging though.

		"${DISTCC_MAKE_J_PARALLEL[@]}" # Parallel compile, "-j X" for X cpus; determined by distcc, or is just "$CTHREADS" if distcc is not enabled.

		"ARCH=${ARCHITECTURE}"         # Key param. Everything depends on this.
		"LOCALVERSION=-${LINUXFAMILY}" # Change the internal kernel version to include the family. Changing this causes recompiles # @TODO change hack at .config; that might handles mtime better

		"CROSS_COMPILE=${CCACHE} ${DISTCC_CROSS_COMPILE_PREFIX[@]} ${KERNEL_COMPILER}" # added as prefix to every compiler invocation by make
		"KCFLAGS=-fdiagnostics-color=always -Wno-error=misleading-indentation"         # Force GCC colored messages, downgrade misleading indentation to warning

		"SOURCE_DATE_EPOCH=${kernel_base_revision_ts}"        # https://reproducible-builds.org/docs/source-date-epoch/ and https://www.kernel.org/doc/html/latest/kbuild/reproducible-builds.html
		"KBUILD_BUILD_TIMESTAMP=${kernel_base_revision_date}" # https://www.kernel.org/doc/html/latest/kbuild/kbuild.html#kbuild-build-timestamp
		"KBUILD_BUILD_USER=armbian"                           # https://www.kernel.org/doc/html/latest/kbuild/kbuild.html#kbuild-build-user-kbuild-build-host
		"KBUILD_BUILD_HOST=next"                              # https://www.kernel.org/doc/html/latest/kbuild/kbuild.html#kbuild-build-user-kbuild-build-host

		"KGZIP=pigz" "KBZIP2=pbzip2" # Parallel compression, use explicit parallel compressors https://lore.kernel.org/lkml/20200901151002.988547791@linuxfoundation.org/ # @TODO: what about XZ?
	)

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

	kernel_compiler_version="$(eval env PATH="${toolchain}:${PATH}" "${KERNEL_COMPILER}gcc" -dumpfullversion -dumpversion)"
	display_alert "Compiler version" "${KERNEL_COMPILER}gcc ${kernel_compiler_version}" "info"
}
