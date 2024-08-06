# Rockchip RK3588S octa core 8GB RAM SoC eMMC USB3 USB2 1x GbE 2x 2.5GbE
BOARD_NAME="NanoPC T6"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="Tonymac32"
BOOTCONFIG="nanopc_t6_defconfig" # vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOT_SOC="rk3588"
KERNEL_TARGET="vendor,current,edge,collabora"
KERNEL_TEST_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588-nanopc-t6.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"
IMAGE_PARTITION_TABLE="gpt"
declare -g UEFI_EDK2_BOARD_ID="nanopc-t6" # This _only_ used for uefi-edk2-rk3588 extension

function post_family_tweaks__nanopct6_naming_audios() {
	display_alert "$BOARD" "Renaming nanopct6 audio" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}

# Mainline u-boot or Kwiboo's tree
function post_family_config_branch_edge__nanopct6_use_mainline_uboot() {
	display_alert "$BOARD" "mainline (next branch) u-boot overrides for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="nanopc-t6-rk3588_defconfig"                    # override the default for the board/family
	declare -g BOOTDELAY=1                                                # Wait for UART interrupt to enter UMS/RockUSB mode etc
	declare -g BOOTSOURCE="https://github.com/Kwiboo/u-boot-rockchip.git" # We ❤️ Kwiboo's tree
	declare -g BOOTBRANCH="branch:rk3xxx-2024.07"                         # commit:xx as of 2024-06-04
	declare -g BOOTPATCHDIR="v2024.04/board_${BOARD}"                     # empty; defconfig changes are done in hook below
	declare -g BOOTDIR="u-boot-${BOARD}"                                  # do not share u-boot directory
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}

	function write_uboot_platform_mtd() {
		flashcp -v -p "$1/u-boot-rockchip-spi.bin" /dev/mtd0
	}
}

function post_config_uboot_target__extra_configs_for_nanopct6_mainline_environment_in_spi() {
	[[ "${BRANCH}" != "edge" ]] && return 0

	display_alert "$BOARD" "u-boot configs for ${BOOTBRANCH} u-boot config BRANCH=${BRANCH}" "info"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_IS_NOWHERE "n"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_IS_IN_SPI_FLASH "y"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_SECT_SIZE_AUTO "y"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_OVERWRITE "y"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_SIZE "0x20000"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_OFFSET "0xc00000"

	display_alert "u-boot for ${BOARD}" "u-boot: enable preboot & flash user LED in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'led user-led on; sleep 0.1; led user-led off'" # double quotes required due to run_host_command_logged's quirks

	display_alert "u-boot for ${BOARD}" "u-boot: enable EFI debugging command" "info"
	run_host_command_logged scripts/config --enable CMD_EFIDEBUG
	run_host_command_logged scripts/config --enable CMD_NVEDIT_EFI

	display_alert "u-boot for ${BOARD}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD

	display_alert "u-boot for ${BOARD}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO

	display_alert "u-boot for ${BOARD}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP_SACK

	# UMS, RockUSB, gadget stuff
	declare -a enable_configs=("CONFIG_CMD_USB_MASS_STORAGE" "CONFIG_USB_GADGET" "USB_GADGET_DOWNLOAD" "CONFIG_USB_FUNCTION_ROCKUSB" "CONFIG_USB_FUNCTION_ACM" "CONFIG_CMD_ROCKUSB" "CONFIG_CMD_USB_MASS_STORAGE")
	for config in "${enable_configs[@]}"; do
		display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable ${config}" "info"
		run_host_command_logged scripts/config --enable "${config}"
	done
	# Auto-enabled by the above, force off...
	run_host_command_logged scripts/config --disable USB_FUNCTION_FASTBOOT

}

# Include fw_setenv, configured to point to the correct spot on the SPI Flash
PACKAGE_LIST_BOARD="libubootenv-tool" # libubootenv-tool provides fw_printenv and fw_setenv, for talking to U-Boot environment
function post_family_tweaks__config_nanopct6_fwenv() {
	[[ "${BRANCH}" != "edge" ]] && return 0
	display_alert "Configuring fw_printenv and fw_setenv" "for ${BOARD} and u-boot ${BOOTBRANCH}" "info"
	# Addresses below come from CONFIG_ENV_OFFSET and CONFIG_ENV_SIZE in defconfig
	cat <<- 'FW_ENV_CONFIG' > "${SDCARD}"/etc/fw_env.config
		# MTD/SPI u-boot env for the ${BOARD_NAME}
		# MTD device name Device offset Env. size Flash sector size Number of sectors
		/dev/mtd0         0xc00000      0x20000
	FW_ENV_CONFIG
}
