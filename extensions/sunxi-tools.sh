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
