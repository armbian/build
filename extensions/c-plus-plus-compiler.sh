# The C++ compiler is no longer included by default in prepare-host.sh.
# Enable this extension if you need a C++ compiler during the build.

function add_host_dependencies__add_arm64_c_plus_plus_compiler() {
	display_alert "Extension: ${EXTENSION}: Adding arm64 c++ compiler to host dependencies" "g++" "debug"

	# Skip cross-compilers that don't exist on non-standard host architectures (e.g. riscv64)
	if [[ "${host_arch}" != "riscv64" ]]; then
		EXTRA_BUILD_DEPS+=("cross-arm64::g++-aarch64-linux-gnu")
	fi

	# Always add the native g++ compiler
	EXTRA_BUILD_DEPS+=("native-toolchain::g++")
}

function host_dependencies_ready__add_arm64_c_plus_plus_compiler() {
	# The arm64 c++ cross-compiler is only declared on hosts where it exists (see above),
	# so only assert its presence there. Fail fast if it was requested but not installed.
	if [[ "${host_arch}" != "riscv64" ]]; then
		# The g++-aarch64-linux-gnu package installs the binary as aarch64-linux-gnu-g++.
		if ! command -v aarch64-linux-gnu-g++ > /dev/null 2>&1 && ! command -v g++-aarch64-linux-gnu > /dev/null 2>&1; then
			exit_with_error "Missing arm64 c++ cross-compiler 'aarch64-linux-gnu-g++'; install g++-aarch64-linux-gnu"
		fi
	fi
}
