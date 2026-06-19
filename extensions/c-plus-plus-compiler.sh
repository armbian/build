# The C++ compiler is no longer included by default in prepare-host.sh.
# Enable this extension if you need a C++ compiler during the build.

function add_host_dependencies__add_arm64_c_plus_plus_compiler() {
	display_alert "Extension: ${EXTENSION}: Adding arm64 c++ compiler to host dependencies" "g++" "debug"
	EXTRA_BUILD_DEPS+=("cross-arm64::g++-aarch64-linux-gnu" "native-toolchain::g++")
}
