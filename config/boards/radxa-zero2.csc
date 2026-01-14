# Amlogic A311D 4GB RAM eMMC USB3 WiFi BT
BOARD_NAME="Radxa Zero 2"
BOARD_VENDOR="radxa"
BOARDFAMILY="meson-g12b"
BOARD_MAINTAINER=""
BOOTCONFIG="radxa-zero2_config"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
MODULES_BLACKLIST="simpledrm" # SimpleDRM conflicts with Panfrost
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
ASOUND_STATE="asound.state.radxa-zero2"
BOOT_FDT_FILE="amlogic/meson-g12b-radxa-zero2.dtb"

BOOTBRANCH_BOARD="tag:v2026.01"
BOOTPATCHDIR="v2026.01"

function post_config_uboot_target__radxa-zero2_fancy_uboot() {
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable preboot & flash user LED in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'led green:status on; sleep 0.1; led green:status off;'" # double quotes required due to run_host_command_logged's quirks

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable EFI debugging commands" "info"
	run_host_command_logged scripts/config --enable CMD_EFIDEBUG
	run_host_command_logged scripts/config --enable CMD_NVEDIT_EFI

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable more filesystems support" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_BTRFS

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable some USB ethernet drivers" "info"
	run_host_command_logged scripts/config --enable CONFIG_USB_HOST_ETHER
	run_host_command_logged scripts/config --enable CONFIG_USB_ETHER_ASIX
	run_host_command_logged scripts/config --enable CONFIG_USB_ETHER_ASIX88179
	run_host_command_logged scripts/config --enable CONFIG_USB_ETHER_MCS7830
	run_host_command_logged scripts/config --enable CONFIG_USB_ETHER_RTL8152
	run_host_command_logged scripts/config --enable CONFIG_USB_ETHER_SMSC95XX

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable LWIP (new networking stack)" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_MII
	run_host_command_logged scripts/config --enable CONFIG_NET_LWIP

	# UMS, RockUSB, gadget stuff
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable UMS/RockUSB gadget" "info"
	declare -a enable_configs=("CONFIG_CMD_USB_MASS_STORAGE" "CONFIG_USB_GADGET" "USB_GADGET_DOWNLOAD" "CONFIG_USB_FUNCTION_ACM")
	for config in "${enable_configs[@]}"; do
		run_host_command_logged scripts/config --enable "${config}"
	done
	# Auto-enabled by the above, force off...
	run_host_command_logged scripts/config --disable USB_FUNCTION_FASTBOOT
}
