#!/usr/bin/env bash

function fetch_sources_tools__gxlimg() {
	fetch_from_repo "https://github.com/retro98boy/gxlimg" "gxlimg" "commit:fde6a3dd0e13875a5b219389c0a6137616eaebdb"
}

function build_host_tools__compile_gxlimg() {
	# Compile and install only if git commit hash changed
	cd "${SRC}/cache/sources/gxlimg" || exit
	# need to check if /usr/local/bin/gxlimg to detect new Docker containers with old cached sources
	if [[ ! -f .commit_id || $(git rev-parse @ 2> /dev/null) != $(< .commit_id) || ! -f /usr/local/bin/gxlimg ]]; then
		display_alert "Compiling" "gxlimg" "info"
		run_host_command_logged make distclean
		run_host_command_logged make
		run_host_command_logged install -Dm0755 gxlimg /usr/local/bin/gxlimg
		git rev-parse @ 2> /dev/null > .commit_id
	fi
}
