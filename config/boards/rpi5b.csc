# Broadcom BCM2712 quad core 1-8Gb RAM SoC USB3 GBE USB-C WiFi/BT
declare -g BOARD_NAME="Raspberry Pi 5"
declare -g BOARDFAMILY="bcm2711"
declare -g BOARD_MAINTAINER=""
declare -g KERNEL_TARGET="current,edge"
declare -g KERNEL_TEST_TARGET="current"
declare -g ASOUND_STATE="asound.state.rpi"

function post_family_config__rename_linux_family() {
	display_alert "rpi5b" "Changing LINUXFAMILY" "info"
	declare -g LINUXFAMILY=bcm2712
}

#function custom_kernel_config__rpi5b_16k_variant() {
#	display_alert "rpi5b" "Enabling 16K page size" "info"
#	kernel_config_modifying_hashes+=(
#		"CONFIG_ARM64_16K_PAGES=y"
#		"CONFIG_ARCH_MMAP_RND_BITS=18"
#		"CONFIG_ARCH_MMAP_RND_COMPAT_BITS=11"
#	)

#	# As kernel config is shared between two variants, override the settings
#	# but make sure not to write them back to config/kernel directory
#	if [[ -f .config ]] && [[ "${KERNEL_CONFIGURE:-yes}" != "yes" ]]; then
#		display_alert "Enabling 16K page size" "armbian-kernel" "debug"
#		kernel_config_set_y CONFIG_ARM64_16K_PAGES
#		run_host_command_logged ./scripts/config --set-val CONFIG_ARCH_MMAP_RND_BITS 18
#		run_host_command_logged ./scripts/config --set-val CONFIG_ARCH_MMAP_RND_COMPAT_BITS 11
#		run_kernel_make olddefconfig
#	fi
#}
