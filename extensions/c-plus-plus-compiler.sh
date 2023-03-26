# The C++ compiler is no longer included by default in prepare-host.sh.
# Enable this extension if you need a C++ compiler during the build.

function add_host_dependencies__add_arm64_c_plus_plus_compiler() {
	display_alert "Adding arm64 c++ compiler to host dependencies" "g++" "debug"
	export EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} g++-aarch64-linux-gnu g++" # @TODO: convert to array later
}
