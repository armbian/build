# Enable Rust support for Linux kernel compilation.
#
# Installs Rust toolchain via rustup into ${SRC}/cache/tools/rustup/ and
# configures the build environment so that CONFIG_RUST appears in kernel
# menuconfig and gets enabled automatically.
#
# The toolchain is cached by a hash of (RUST_VERSION, BINDGEN_VERSION, arch,
# RUST_EXTRA_COMPONENTS, RUST_EXTRA_CARGO_CRATES). Changing any of these
# triggers a full reinstall on the next build.
#
# Other extensions can request additional rustup components or cargo crates:
#   RUST_EXTRA_COMPONENTS+=("clippy" "llvm-tools")
#   RUST_EXTRA_CARGO_CRATES+=("mdbook" "cargo-deb@2.11.0")
#
# Usage:  ./compile.sh kernel-config BOARD=... BRANCH=... ENABLE_EXTENSIONS="kernel-rust"
#
# References:
#   https://docs.kernel.org/rust/quick-start.html
#   https://docs.kernel.org/rust/general-information.html
#   https://rust-for-linux.com/rust-version-policy
#   https://rust-lang.github.io/rustup/installation/index.html

# Rust toolchain version installed via rustup.
# Kernel >= 6.12 requires rustc >= 1.78. See rust-version-policy above.
RUST_VERSION="${RUST_VERSION:-1.85.0}"

# bindgen-cli version installed via cargo.
# APT bindgen 0.66.1 panics on kernel >= 6.19 headers (FromBytesWithNulError
# in codegen/mod.rs). Fixed in >= 0.69.
BINDGEN_VERSION="${BINDGEN_VERSION:-0.71.1}"

# Enable Rust sample kernel modules for toolchain smoke testing.
# Set to "yes" to build rust_minimal, rust_print, rust_driver_faux as modules.
# Can also be set via command line: RUST_KERNEL_SAMPLES=yes
RUST_KERNEL_SAMPLES="${RUST_KERNEL_SAMPLES:-no}"

# Extra rustup components to install (e.g. clippy, llvm-tools).
# Other extensions can append: RUST_EXTRA_COMPONENTS+=("clippy")
declare -g -a RUST_EXTRA_COMPONENTS=()

# Extra cargo crates to install. Supports "name" or "name@version" syntax.
# Other extensions can append: RUST_EXTRA_CARGO_CRATES+=("mdbook" "cargo-deb@2.11.0")
declare -g -a RUST_EXTRA_CARGO_CRATES=()

# Resolved tool paths, set by host_dependencies_ready, used by custom_kernel_make_params.
declare -g RUST_TOOL_RUSTC=""
declare -g RUST_TOOL_RUSTFMT=""
declare -g RUST_TOOL_BINDGEN=""
declare -g RUST_TOOL_SYSROOT=""

function add_host_dependencies__add_rust_compiler() {
	display_alert "Adding Rust kernel build dependencies" "${EXTENSION}" "info"
	# bindgen needs libclang for dlopen; available on all target distros.
	EXTRA_BUILD_DEPS+=" libclang-dev "
}

# Download rustup-init binary for the current architecture.
# Follows the project pattern: curl → .tmp → mv → chmod.
_download_rustup_init() {
	local target_dir="$1"
	local target_triple
	case "${BASH_VERSINFO[5]}" in
		*aarch64*) target_triple="aarch64-unknown-linux-gnu" ;;
		*x86_64*) target_triple="x86_64-unknown-linux-gnu" ;;
		*riscv64*) target_triple="riscv64gc-unknown-linux-gnu" ;;
		*) exit_with_error "Unsupported architecture for rustup" "${BASH_VERSINFO[5]}" ;;
	esac

	local url="https://static.rust-lang.org/rustup/dist/${target_triple}/rustup-init"
	local dest="${target_dir}/rustup-init"

	display_alert "Downloading rustup-init" "${target_triple}" "info"
	curl --proto '=https' --tlsv1.2 -sSf -o "${dest}.tmp" "${url}"
	mv "${dest}.tmp" "${dest}"
	chmod +x "${dest}"
}

# Install or reuse cached Rust toolchain in ${SRC}/cache/tools/rustup/.
_prepare_rust_toolchain() {
	local rust_cache_dir="${SRC}/cache/tools/rustup"
	mkdir -p "${rust_cache_dir}"

	local rustup_home="${rust_cache_dir}/rustup-home"
	local cargo_home="${rust_cache_dir}/cargo-home"

	# Content-addressable cache: hash of version config + architecture + extras
	local cache_key="${RUST_VERSION}|${BINDGEN_VERSION}|${BASH_VERSINFO[5]}"
	cache_key+="|${RUST_EXTRA_COMPONENTS[*]}|${RUST_EXTRA_CARGO_CRATES[*]}"
	local cache_hash
	cache_hash="$(echo -n "${cache_key}" | sha256sum | cut -c1-16)"
	local marker="${rust_cache_dir}/.marker-${cache_hash}"

	if [[ -f "${marker}" ]]; then
		display_alert "Rust toolchain cache hit" "${cache_hash}" "cachehit"
		return 0
	fi

	# Remove stale markers from previous versions
	rm -f "${rust_cache_dir}"/.marker-*

	display_alert "Installing Rust toolchain" "rustc ${RUST_VERSION}, bindgen ${BINDGEN_VERSION}" "info"

	# Download rustup-init
	do_with_retries 3 _download_rustup_init "${rust_cache_dir}"

	# Install minimal toolchain; SKIP_PATH_CHECK suppresses warnings about
	# system rustc in /usr/bin (e.g. from mtkflash in Docker images).
	RUSTUP_HOME="${rustup_home}" CARGO_HOME="${cargo_home}" \
		RUSTUP_INIT_SKIP_PATH_CHECK=yes \
		"${rust_cache_dir}/rustup-init" -y \
		--profile minimal \
		--default-toolchain "${RUST_VERSION}" \
		--no-modify-path

	# Components: rustfmt (not in minimal profile) + rust-src (kernel needs it) + extras
	local -a components=(rustfmt rust-src "${RUST_EXTRA_COMPONENTS[@]}")
	display_alert "Installing rustup components" "${components[*]}" "info"
	RUSTUP_HOME="${rustup_home}" CARGO_HOME="${cargo_home}" \
		"${cargo_home}/bin/rustup" component add "${components[@]}"

	# Cargo crates: bindgen-cli (kernel needs it) + extras
	# Supports "name" or "name@version" syntax.
	local -a crates=("bindgen-cli@${BINDGEN_VERSION}" "${RUST_EXTRA_CARGO_CRATES[@]}")
	local crate
	for crate in "${crates[@]}"; do
		display_alert "Installing cargo crate" "${crate}" "info"
		RUSTUP_HOME="${rustup_home}" CARGO_HOME="${cargo_home}" \
			"${cargo_home}/bin/cargo" install --locked "${crate}"
	done

	# Mark cache as valid only after everything succeeds
	touch "${marker}"
	display_alert "Rust toolchain installed" "${cache_hash}" "info"
}

# Resolve absolute paths to Rust tool binaries.
# Uses direct paths into the toolchain (not rustup proxies), so that
# env -i in run_kernel_make_internal() does not need RUSTUP_HOME set.
_resolve_rust_tool_paths() {
	local rustup_home="${SRC}/cache/tools/rustup/rustup-home"
	local cargo_home="${SRC}/cache/tools/rustup/cargo-home"

	RUST_TOOL_SYSROOT="$(RUSTUP_HOME="${rustup_home}" CARGO_HOME="${cargo_home}" \
		"${cargo_home}/bin/rustc" --print sysroot)"

	# Direct binaries inside the toolchain, bypassing rustup proxy
	RUST_TOOL_RUSTC="${RUST_TOOL_SYSROOT}/bin/rustc"
	RUST_TOOL_RUSTFMT="${RUST_TOOL_SYSROOT}/bin/rustfmt"
	RUST_TOOL_BINDGEN="${cargo_home}/bin/bindgen"
}

function host_dependencies_ready__add_rust_compiler() {
	_prepare_rust_toolchain
	_resolve_rust_tool_paths

	# Verify all tools are executable
	local tool_name tool_path
	for tool_name in RUST_TOOL_RUSTC RUST_TOOL_RUSTFMT RUST_TOOL_BINDGEN; do
		tool_path="${!tool_name}"
		[[ -x "${tool_path}" ]] || exit_with_error "Required Rust tool '${tool_name}' not found at ${tool_path}" "${EXTENSION}"
	done

	display_alert "Rust toolchain ready" \
		"rustc $(${RUST_TOOL_RUSTC} --version | awk '{print $2}'), bindgen $(${RUST_TOOL_BINDGEN} --version 2>&1 | awk '{print $2}')" "info"
}

function artifact_kernel_version_parts__add_rust_version() {
	# Include Rust toolchain version in artifact hash so that changing
	# RUST_VERSION or BINDGEN_VERSION triggers a kernel rebuild.
	local cache_key="${RUST_VERSION}|${BINDGEN_VERSION}"
	local short
	short="$(echo -n "${cache_key}" | sha256sum | cut -c1-4)"

	artifact_version_parts["_R"]="rust${short}"

	# Add to order array if not already present
	local found=0 entry
	for entry in "${artifact_version_part_order[@]}"; do
		[[ "${entry}" == *"-_R" ]] && found=1 && break
	done
	if [[ "${found}" -eq 0 ]]; then
		artifact_version_part_order+=("0086-_R")
	fi
}

function custom_kernel_config__add_rust_compiler() {
	# https://docs.kernel.org/rust/quick-start.html
	opts_y+=("RUST")

	# Build sample Rust modules for toolchain smoke testing
	if [[ "${RUST_KERNEL_SAMPLES}" == "yes" ]]; then
		display_alert "Enabling Rust sample modules" "${EXTENSION}" "info"
		opts_y+=("SAMPLES") # Parent menu for all kernel samples
		opts_y+=("SAMPLES_RUST")
		opts_m+=("SAMPLE_RUST_MINIMAL")
		opts_m+=("SAMPLE_RUST_PRINT")
		opts_m+=("SAMPLE_RUST_DRIVER_FAUX")
	fi
}

function custom_kernel_make_params__add_rust_compiler() {
	# run_kernel_make_internal uses "env -i" which clears all environment
	# variables, so we pass Rust paths explicitly via make parameters.
	# Using direct toolchain binaries (not rustup proxies) avoids needing
	# RUSTUP_HOME in the env -i context.

	common_make_params_quoted+=("RUSTC=${RUST_TOOL_RUSTC}")
	common_make_params_quoted+=("RUSTFMT=${RUST_TOOL_RUSTFMT}")
	common_make_params_quoted+=("BINDGEN=${RUST_TOOL_BINDGEN}")

	# Rust standard library source path for kernel build
	local rust_lib_src="${RUST_TOOL_SYSROOT}/lib/rustlib/src/rust/library"
	if [[ -d "${rust_lib_src}" ]]; then
		display_alert "Rust library source" "${rust_lib_src}" "info"
		common_make_envs+=("RUST_LIB_SRC='${rust_lib_src}'")
	else
		display_alert "Rust library source not found" "CONFIG_RUST will not appear in menuconfig" "wrn"
	fi
}
