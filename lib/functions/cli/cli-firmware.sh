function cli_firmware_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_firmware_run() {

	# configuration etc - it initializes the extension manager; handles its own logging sections.
	prep_conf_main_only_firmware < /dev/null # no stdin for this, so it bombs if tries to be interactive.

	# Minimal config needed
	declare -g -r BOARD_FIRMWARE_INSTALL="-full" # Build full firmware "too"

	# Fool the preparation step; firmware is arch agnostic.
	declare -g -r ARCH=arm64

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

# Lean version, for building rootfs, that doesn't need BOARD/BOARDFAMILY; never interactive.
function prep_conf_main_only_firmware() {
	LOG_SECTION="config_early_init" do_with_conditional_logging config_early_init

	check_basic_host

	LOG_SECTION="config_pre_main" do_with_conditional_logging config_pre_main

	allow_no_family="yes" \
		LOG_SECTION="do_main_configuration" do_with_conditional_logging do_main_configuration # This initializes the extension manager among a lot of other things, and call extension_prepare_config() hook

	LOG_SECTION="do_extra_configuration" do_with_conditional_logging do_extra_configuration

	skip_kernel="yes" \
		LOG_SECTION="config_post_main" do_with_conditional_logging config_post_main

	display_alert "Configuration prepared for non-BOARD build" "prep_conf_main_only_rootfs" "info"
}
