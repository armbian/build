# The C++ compiler is no longer included by default in prepare-host.sh.
# Enable this extension if you need a C++ compiler during the build.

function add_host_dependencies__add_arm64_c_plus_plus_compiler() {
	display_alert "Extension: ${EXTENSION}: Adding arm64 c++ compiler to host dependencies" "g++" "debug"

	# Skip cross-compilers that don't exist on non-standard host architectures (e.g., riscv64)
	if [[ "${host_arch}" != "riscv64" ]]; then
		declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} g++-aarch64-linux-gnu" # @TODO: convert to array later
	fi

	# Always add the native g++ compiler
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} g++" # @TODO: convert to array later
}
