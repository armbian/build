# Enable 32-bit compat vDSO for arm64 kernels with GCC or clang.
# Requirements:
# - arm64 build target (ARCH=arm64, ARCHITECTURE=arm64).
# - For GCC builds: a 32-bit ARM cross-compiler (default prefix arm-linux-gnueabi-),
#   available as ${CROSS_COMPILE_COMPAT}gcc; install gcc-arm-linux-gnueabi or set CROSS_COMPILE_COMPAT.
# - For clang builds: clang present; compat vDSO is built via clang --target=arm-linux-gnueabi.

function extension_prepare_config__arm64_compat_vdso() {
	if [[ "${ARCH}" != "arm64" || "${ARCHITECTURE}" != "arm64" ]]; then
		exit_with_error "arm64-only extension: ARCH=${ARCH} ARCHITECTURE=${ARCHITECTURE}"
	fi
}

function add_host_dependencies__arm64_compat_vdso() {
	if [[ "${KERNEL_COMPILER}" == "clang" ]]; then
		EXTRA_BUILD_DEPS+=" clang "
	else
		EXTRA_BUILD_DEPS+=" gcc-arm-linux-gnueabi "
	fi
}

function host_dependencies_ready__arm64_compat_vdso() {
	if [[ "${KERNEL_COMPILER}" == "clang" ]]; then
		return 0
	fi

	local compat_gcc_prefix="${CROSS_COMPILE_COMPAT:-"arm-linux-gnueabi-"}"
	if ! command -v "${compat_gcc_prefix}gcc" >/dev/null 2>&1; then
		exit_with_error "Missing 32-bit compiler '${compat_gcc_prefix}gcc' for COMPAT_VDSO; install gcc-arm-linux-gnueabi or set CROSS_COMPILE_COMPAT"
	fi
}

function custom_kernel_make_params__arm64_compat_vdso() {
	if [[ "${KERNEL_COMPILER}" == "clang" ]]; then
		return 0
	fi

	local compat_gcc_compiler="${CROSS_COMPILE_COMPAT:-"arm-linux-gnueabi-"}"
	common_make_params_quoted+=("CROSS_COMPILE_COMPAT=${compat_gcc_compiler}")
	display_alert "arm64-compat-vdso" "Adding CROSS_COMPILE_COMPAT=${compat_gcc_compiler}" "info"
}

function custom_kernel_config__arm64_compat_vdso() {
	local kconfig_hit=""

	opts_y+=("COMPAT" "COMPAT_VDSO" "ARM64_32BIT_EL0")

	if [[ -f .config ]]; then
		kconfig_hit="$(grep -R -n -m1 "COMPAT_VDSO" arch/arm64 Kconfig* 2>/dev/null || true)"
		if [[ -z "${kconfig_hit}" ]]; then
			exit_with_error "Selected kernel tree lacks COMPAT_VDSO support for arm64"
		fi
	fi
}
