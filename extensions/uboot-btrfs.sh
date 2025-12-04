# Enable BTRFS support in u-boot

function post_config_uboot_target__enable_uboot_btrfs_support() {
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable BTRFS filesystem support" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_BTRFS
}
