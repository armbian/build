function cli_rootfs_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes" # Require prepare_host_basic to run before the command.

	# "gimme root on a Linux machine"
	cli_standard_relaunch_docker_or_sudo
}

function cli_rootfs_run() {
	# configuration etc - it initializes the extension manager; handles its own logging sections
	prep_conf_main_build_single

	# default build, but only invoke specific rootfs functions needed. It has its own logging sections.
	do_with_default_build cli_rootfs_only_in_default_build
}

# This is run inside do_with_default_build(), above.
function cli_rootfs_only_in_default_build() {
	LOG_SECTION="prepare_rootfs_build_params_and_trap" do_with_logging prepare_rootfs_build_params_and_trap

	LOG_SECTION="calculate_rootfs_cache_id" do_with_logging calculate_rootfs_cache_id

	# "rootfs" CLI skips over a lot goes straight to create the rootfs. It doesn't check cache etc.
	LOG_SECTION="create_new_rootfs_cache" do_with_logging create_new_rootfs_cache
}
