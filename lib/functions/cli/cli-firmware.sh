function cli_firmware_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_firmware_run() {

	# minimal, non-interactive configuration - it initializes the extension manager; handles its own logging sections.
	prep_conf_main_minimal_ni < /dev/null # no stdin for this, so it bombs if tries to be interactive.

	declare -g -r BOARD_FIRMWARE_INSTALL="-full" # Build full firmware "too"; overrides the config

	# default build, but only invoke specific rootfs functions needed. It has its own logging sections.
	do_with_default_build cli_firmware_only_in_default_build < /dev/null # no stdin for this, so it bombs if tries to be interactive.

	#reset_uid_owner "${BUILT_ROOTFS_CACHE_FILE}"

	display_alert "Firmware build complete" "fake" "info"
}

# This is run inside do_with_default_build(), above.
function cli_firmware_only_in_default_build() {
	github_actions_add_output firmware_version "fake"
	compile_firmware_light_and_possibly_full
}
