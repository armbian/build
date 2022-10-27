function cli_distccd_pre_run() {
	: <<- 'HEADER'
		Sets up an inline extension to include distccd in dependencies.
	HEADER
	display_alert "cli_distccd_pre_run" "func cli_distccd_run :: ${ARMBIAN_COMMAND}" "warn"

	# When being relaunched in Docker, I wanna add port-forwardings to the distccd ports.
	declare -g DOCKER_EXTRA_ARGS+=("-p" "3632:3632" "-p" "3633:3633")

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_distccd_run() {
	: <<- 'HEADER'
		Runs distccd in the foreground.
	HEADER

	# Initialize the extension manager. distccd has no boards/etc.
	initialize_extension_manager

	# Install hostdeps. Call directly the requirements cli command, they know what they're doing.
	cli_requirements_run

	display_alert "cli_distccd_run" "func cli_distccd_run" "warn"

	# remove all bash traps
	trap - INT TERM EXIT

	# @TODO: --zeroconf (not if under Docker)
	# @TODO: --jobs (CPU count!)
	display_alert "Run it yourself" "distccd --allow-private --verbose --no-detach --daemon --stats --log-level info --log-stderr --listen 0.0.0.0 --zeroconf" "warn"
}
