# Enable Rust support for Linux kernel compilation.
#
# Installs Rust toolchain and configures the build environment so that
# CONFIG_RUST appears in kernel menuconfig and gets enabled automatically.
#
# Two installation methods are available (toggle by commenting/uncommenting):
#   1. APT packages: versioned rustc from noble-security (default)
#   2. Rustup: latest stable from rustup.rs (commented out)
#
# Usage:  ./compile.sh kernel-config BOARD=... BRANCH=... ENABLE_EXTENSIONS="kernel-rust"
#
# References:
#   https://docs.kernel.org/rust/quick-start.html
#   https://docs.kernel.org/rust/general-information.html
#   https://rust-for-linux.com/rust-version-policy
#   https://rust-lang.github.io/rustup/installation/index.html

# Rust version for APT method. Available in noble-security/noble-updates.
# Kernel >= 6.12 requires rustc >= 1.78. See:
#   https://launchpad.net/ubuntu/noble/+package/cargo-1.85
RUST_APT_VERSION="1.85"

# bindgen version for APT method. APT bindgen 0.66.1 panics on kernel >= 6.19
# headers (FromBytesWithNulError in codegen/mod.rs). Fixed in >= 0.69.
# bindgen-0.71 is available in noble-updates since 2026-02-02. See:
#   https://launchpad.net/ubuntu/noble/arm64/bindgen-0.71
BINDGEN_APT_VERSION="0.71"

# LLVM/Clang version must match the libclang that bindgen links against.
# Auto-detect by resolving the dependency chain:
#   bindgen-0.71 → libclang-20-dev          (versioned, Ubuntu 24.04)
#   bindgen      → libclang-dev → libclang-NN-dev  (unversioned, Debian/newer Ubuntu)
# Using mismatched versions (e.g. clang-18 + libclang-20) triggers a kernel
# warning at "make rustavailable" time.
_detect_llvm_version() {
	local bindgen_pkg ver candidate
	# Try versioned bindgen first (Ubuntu 24.04), then unversioned.
	# Only query real (installable) packages — virtual packages like
	# bindgen-0.71 on Trixie return provider lists that contain
	# "testing-only-libclang-16" strings, producing false matches.
	for bindgen_pkg in "bindgen-${BINDGEN_APT_VERSION}" "bindgen"; do
		candidate="$(apt-cache policy "${bindgen_pkg}" 2> /dev/null \
			| sed -n 's/.*Candidate: *//p')"
		[[ -n "${candidate}" && "${candidate}" != "(none)" ]] || continue
		# Parse only "Depends:" lines, not virtual package providers
		ver="$(apt-cache depends "${bindgen_pkg}" 2> /dev/null \
			| sed -n 's/^[[:space:]]*Depends:.*libclang-\([0-9]\+\)-dev.*/\1/p' | head -1)"
		if [[ -n "${ver}" ]]; then
			echo "${ver}"
			return
		fi
	done
	# Unversioned libclang-dev → resolve to libclang-NN-dev
	ver="$(apt-cache depends libclang-dev 2> /dev/null \
		| sed -n 's/^[[:space:]]*Depends:.*libclang-\([0-9]\+\)-dev.*/\1/p' | head -1)"
	if [[ -n "${ver}" ]]; then
		echo "${ver}"
		return
	fi
}
LLVM_APT_VERSION="$(_detect_llvm_version)" || true
LLVM_APT_VERSION="${LLVM_APT_VERSION:-20}" # fallback if apt-cache unavailable
unset -f _detect_llvm_version

# Enable Rust sample kernel modules for toolchain smoke testing.
# Set to "yes" to build rust_minimal, rust_print, rust_driver_faux as modules.
# Can also be set via command line: RUST_KERNEL_SAMPLES=yes
RUST_KERNEL_SAMPLES="${RUST_KERNEL_SAMPLES:-no}"

# Resolved tool paths, set by host_dependencies_ready, used by custom_kernel_make_params.
declare -g RUST_TOOL_RUSTC=""
declare -g RUST_TOOL_RUSTFMT=""
declare -g RUST_TOOL_BINDGEN=""

function add_host_dependencies__add_rust_compiler() {
	display_alert "Adding Rust kernel build dependencies" "${EXTENSION}" "info"

	# Rust packages: try versioned first (Ubuntu 24.04), fall back to unversioned
	# (Debian trixie, Ubuntu >= 25.10). _apt_pick outputs the first available.
	local pkg
	for pkg in rustc cargo rustfmt; do
		EXTRA_BUILD_DEPS+=" $(_apt_pick "${pkg}-${RUST_APT_VERSION}" "${pkg}") "
	done
	EXTRA_BUILD_DEPS+=" $(_apt_pick "rust-${RUST_APT_VERSION}-src" rust-src) "
	EXTRA_BUILD_DEPS+=" $(_apt_pick "bindgen-${BINDGEN_APT_VERSION}" bindgen) "

	# LLVM toolchain: versioned to match libclang used by bindgen
	EXTRA_BUILD_DEPS+=" clang-${LLVM_APT_VERSION} lld-${LLVM_APT_VERSION} llvm-${LLVM_APT_VERSION} "
}

# Pick first installable APT package from candidates.
# Uses apt-cache policy to distinguish real packages from virtual ones
# (apt-cache show returns 0 for virtual packages like bindgen-0.71 on Trixie).
_apt_pick() {
	local pkg candidate
	for pkg in "$@"; do
		candidate="$(apt-cache policy "${pkg}" 2> /dev/null \
			| sed -n 's/.*Candidate: *//p' | head -1)"
		if [[ -n "${candidate}" && "${candidate}" != "(none)" ]]; then
			echo "${pkg}"
			return
		fi
	done
	# None found — return first candidate and let apt fail with a clear error
	echo "$1"
}

# Find a versioned tool binary, returning its full path.
# Priority: versioned name in PATH > dpkg package file list > unversioned in PATH.
# The unversioned fallback is last to avoid picking up an older system tool
# (e.g. rustc 1.75 from mtkflash) over the requested versioned package.
_find_rust_tool() {
	local base="$1" version="$2"
	local tool_path=""
	# 1. Try versioned command in PATH (e.g. rustc-1.85)
	if [[ -n "${version}" ]]; then
		local versioned="${base}-${version}"
		tool_path="$(command -v "${versioned}" 2> /dev/null || true)"
		if [[ -n "${tool_path}" ]]; then
			echo "${tool_path}"
			return
		fi
		# 2. Locate binary via dpkg package file list
		if dpkg -s "${versioned}" > /dev/null 2>&1; then
			tool_path="$(dpkg -L "${versioned}" 2> /dev/null | grep "/bin/${base}" | head -1 || true)"
			if [[ -n "${tool_path}" && -x "${tool_path}" ]]; then
				display_alert "Found ${base} via dpkg" "${tool_path}" "info"
				echo "${tool_path}"
				return
			fi
		fi
	fi
	# 3. Last resort: unversioned command in PATH
	tool_path="$(command -v "${base}" 2> /dev/null || true)"
	if [[ -n "${tool_path}" ]]; then
		echo "${tool_path}"
		return
	fi
}

function host_dependencies_ready__add_rust_compiler() {
	# --- Method 1: APT versioned packages ---
	RUST_TOOL_RUSTC="$(_find_rust_tool rustc "${RUST_APT_VERSION}")"
	RUST_TOOL_RUSTFMT="$(_find_rust_tool rustfmt "${RUST_APT_VERSION}")"
	RUST_TOOL_BINDGEN="$(_find_rust_tool bindgen "${BINDGEN_APT_VERSION}")"

	local tool_name tool_path
	for tool_name in RUST_TOOL_RUSTC RUST_TOOL_RUSTFMT RUST_TOOL_BINDGEN; do
		tool_path="${!tool_name}"
		[[ -n "${tool_path}" ]] || _missing_rust_tool_abort "${tool_name}"
	done

	display_alert "Rust toolchain ready" \
		"${RUST_TOOL_RUSTC} $(${RUST_TOOL_RUSTC} --version | awk '{print $2}'), bindgen $(${RUST_TOOL_BINDGEN} --version 2>&1 | awk '{print $2}')" "info"

	# --- Method 2: Rustup (commented out) ---
	## Remove outdated system rustc/cargo if present (e.g. from mtkflash
	## extension which adds them to the Docker image packages).
	#if command -v dpkg > /dev/null 2>&1 && dpkg -s rustc > /dev/null 2>&1; then
	#	display_alert "Removing outdated system Rust packages" "${EXTENSION}" "info"
	#	apt-get remove -y --autoremove rustc cargo 2>/dev/null || true
	#fi
	#
	#if [[ ! -f "$HOME/.cargo/bin/rustc" ]]; then
	#	display_alert "Installing Rust toolchain via rustup" "${EXTENSION}" "info"
	#	# https://rust-lang.github.io/rustup/installation/index.html
	#	RUSTUP_INIT_SKIP_PATH_CHECK=yes \
	#		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
	#		| sh -s -- -y --profile minimal --default-toolchain stable
	#fi
	#
	#export PATH="$HOME/.cargo/bin:$PATH"
	#
	## rust-src: Rust standard library source (required by kernel build)
	#rustup component add rust-src
	#
	## bindgen: generates Rust FFI bindings from C kernel headers
	#if ! command -v bindgen > /dev/null 2>&1; then
	#	display_alert "Installing bindgen-cli via cargo" "${EXTENSION}" "info"
	#	cargo install --locked bindgen-cli
	#fi
	#
	#RUST_TOOL_RUSTC="rustc"
	#RUST_TOOL_RUSTFMT="rustfmt"
	#RUST_TOOL_BINDGEN="bindgen"
	#
	#local tool
	#for tool in rustc rustfmt bindgen; do
	#	if ! command -v "${tool}" > /dev/null 2>&1; then
	#		exit_with_error "Required Rust tool '${tool}' not found" "${EXTENSION}"
	#	fi
	#done
	#
	#display_alert "Rust toolchain ready" \
	#	"rustc $(rustc --version | awk '{print $2}'), bindgen $(bindgen --version 2>&1 | awk '{print $2}')" "info"
}

_show_dpkg_bins() {
	local pkg
	for pkg in "$@"; do
		display_alert "dpkg -L ${pkg}" \
			"$(dpkg -L "${pkg}" 2>&1 | grep bin || echo 'N/A')" "wrn"
	done
}

_missing_rust_tool_abort() {
	local tool_name="$1"
	display_alert "PATH" "${PATH}" "wrn"
	_show_dpkg_bins "rustfmt-${RUST_APT_VERSION}" "rustc-${RUST_APT_VERSION}" "bindgen-${BINDGEN_APT_VERSION}"
	exit_with_error "Required Rust tool '${tool_name}' not found" "${EXTENSION}"
}

# Override the compiler version in artifact hash when using versioned clang.
# kernel-version-toolchain (if enabled) sets _T from unversioned "clang" in PATH,
# but this extension redirects the build to clang-VER via LLVM=-VER.
# Runs after add_toolchain (alphabetically: "override" > "add").
function artifact_kernel_version_parts__override_toolchain_version() {
	[[ "${KERNEL_COMPILER}" == "clang" && -n "${LLVM_APT_VERSION}" ]] || return 0
	local clang_bin="clang-${LLVM_APT_VERSION}"
	command -v "${clang_bin}" &> /dev/null || return 0

	local full_version short_version
	full_version="$("${clang_bin}" -dumpfullversion -dumpversion 2> /dev/null || echo "")"
	[[ -n "${full_version}" ]] || return 0
	short_version="$(echo "${full_version}" | cut -d'.' -f1-2)"

	artifact_version_parts["_T"]="clang${short_version}"
	# Ensure the key is in the order array (kernel-version-toolchain may have added it,
	# but if that extension is not enabled, we need to add it ourselves)
	local found=0 entry
	for entry in "${artifact_version_part_order[@]}"; do
		[[ "${entry}" == *"-_T" ]] && found=1 && break
	done
	if [[ "${found}" -eq 0 ]]; then
		artifact_version_part_order+=("0085-_T")
	fi
}

function custom_kernel_config__add_rust_compiler() {
	# https://docs.kernel.org/rust/quick-start.html
	opts_y+=("RUST")

	# Build sample Rust modules for toolchain smoke testing
	if [[ "${RUST_KERNEL_SAMPLES}" == "yes" ]]; then
		display_alert "Enabling Rust sample modules" "${EXTENSION}" "info"
		opts_y+=("SAMPLES")        # Parent menu for all kernel samples
		opts_y+=("SAMPLES_RUST")
		opts_m+=("SAMPLE_RUST_MINIMAL")
		opts_m+=("SAMPLE_RUST_PRINT")
		opts_m+=("SAMPLE_RUST_DRIVER_FAUX")
	fi
}

function custom_kernel_make_params__add_rust_compiler() {
	# run_kernel_make_internal uses "env -i" which clears all environment
	# variables, so we must pass Rust paths explicitly.

	# When building with clang, replace LLVM=1 with LLVM=-VER so that the
	# kernel uses versioned LLVM tools (clang-20, ld.lld-20, llvm-ar-20, …)
	# matching the libclang version that bindgen links against.
	# Also update CC= to use versioned clang, because kernel-make.sh sets
	# CC=ccache clang (unversioned) which overrides the CC that LLVM=-VER
	# would derive in the kernel Makefile.
	# See: https://docs.kernel.org/kbuild/llvm.html#llvm-utility
	if [[ "${KERNEL_COMPILER}" == "clang" && -n "${LLVM_APT_VERSION}" ]]; then
		local i
		for i in "${!common_make_params_quoted[@]}"; do
			case "${common_make_params_quoted[${i}]}" in
				LLVM=1)
					common_make_params_quoted[${i}]="LLVM=-${LLVM_APT_VERSION}"
					display_alert "Using versioned LLVM toolchain" "LLVM=-${LLVM_APT_VERSION}" "info"
					;;
				CC=*clang)
					# Replace "CC=ccache clang" → "CC=ccache clang-20"
					common_make_params_quoted[${i}]="${common_make_params_quoted[${i}]/%clang/clang-${LLVM_APT_VERSION}}"
					display_alert "Using versioned clang" "clang-${LLVM_APT_VERSION}" "info"
					;;
			esac
		done
	fi

	# --- Method 1: APT versioned packages ---
	# Tell the kernel build system to use the discovered tool names.
	if [[ -n "${RUST_TOOL_RUSTC}" ]]; then
		common_make_params_quoted+=("RUSTC=${RUST_TOOL_RUSTC}")
	fi
	if [[ -n "${RUST_TOOL_RUSTFMT}" ]]; then
		common_make_params_quoted+=("RUSTFMT=${RUST_TOOL_RUSTFMT}")
	fi
	if [[ -n "${RUST_TOOL_BINDGEN}" ]]; then
		common_make_params_quoted+=("BINDGEN=${RUST_TOOL_BINDGEN}")
	fi

	# Determine RUST_LIB_SRC for APT rust-src package.
	# Debian/Ubuntu: rust-X.YY-src installs to /usr/src/rustc-FULL_VER/library/
	local rust_lib_src=""
	if [[ -n "${RUST_TOOL_RUSTC}" ]]; then
		local rustc_full_version
		rustc_full_version="$(${RUST_TOOL_RUSTC} --version | awk '{print $2}')"

		if [[ -d "/usr/src/rustc-${rustc_full_version}/library" ]]; then
			rust_lib_src="/usr/src/rustc-${rustc_full_version}/library"
		fi
	fi

	# --- Method 2: Rustup (commented out) ---
	## rustup installs rust-src to $(rustc --print sysroot)/lib/rustlib/src/rust/library/
	#local rust_sysroot
	#rust_sysroot="$(rustc --print sysroot 2>/dev/null)"
	#if [[ -d "${rust_sysroot}/lib/rustlib/src/rust/library" ]]; then
	#	rust_lib_src="${rust_sysroot}/lib/rustlib/src/rust/library"
	#fi

	if [[ -n "${rust_lib_src}" ]]; then
		display_alert "Rust library source" "${rust_lib_src}" "info"
		common_make_envs+=("RUST_LIB_SRC='${rust_lib_src}'")
	else
		display_alert "Rust library source not found" "CONFIG_RUST will not appear in menuconfig" "wrn"
	fi
}
