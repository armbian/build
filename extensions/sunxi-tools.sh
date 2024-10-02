#!/usr/bin/env bash

# Most sunxi stuff, even if 64-bit, requires 32-bit compiler, add it.
# This is only used for non-Docker, since the Docker image already has it, since it includes compilers for all architectures.
function add_host_dependencies__sunxi_add_32_bit_c_compiler() {
	display_alert "Adding armhf C compiler to host dependencies" "for sunxi bootloader compile" "debug"
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} gcc-arm-linux-gnueabi" # @TODO: convert to array later
}

# Install gcc-or1k-elf for crust compilation
function add_host_dependencies__sunxi_add_or1k_c_compiler() {
	display_alert "Adding or1k C compiler to host dependencies" "for sunxi bootloader compile" "debug"
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} gcc-or1k-elf"
}

function fetch_sources_tools__sunxi_tools() {
	fetch_from_repo "https://github.com/linux-sunxi/sunxi-tools" "sunxi-tools" "branch:master"
}

function build_host_tools__compile_sunxi_tools() {
	# Compile and install only if git commit hash changed
	cd "${SRC}"/cache/sources/sunxi-tools || exit
	# need to check if /usr/local/bin/sunxi-fexc to detect new Docker containers with old cached sources
	if [[ ! -f .commit_id || $(git rev-parse @ 2> /dev/null) != $(< .commit_id) || ! -f /usr/local/bin/sunxi-fexc ]]; then
		display_alert "Compiling" "sunxi-tools" "info"
		run_host_command_logged make -s clean
		run_host_command_logged make -s tools
		mkdir -p /usr/local/bin/
		run_host_command_logged make install-tools
		git rev-parse @ 2> /dev/null > .commit_id
	fi
}
