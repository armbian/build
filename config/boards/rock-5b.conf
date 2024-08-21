# Rockchip RK3588 SoC octa core 4-16GB SoC 2.5GBe PoE eMMC USB3 NvME
BOARD_NAME="Rock 5B"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="amazingfate linhz0hz"
BOOTCONFIG="rock-5b-rk3588_defconfig"
KERNEL_TARGET="edge,current,vendor"
KERNEL_TEST_TARGET="vendor,current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588-rock-5b.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"
IMAGE_PARTITION_TABLE="gpt"
declare -g UEFI_EDK2_BOARD_ID="rock-5b" # This _only_ used for uefi-edk2-rk3588 extension

function post_family_tweaks__rock5b_naming_audios() {
	display_alert "$BOARD" "Renaming rock5b audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi1-sound", ENV{SOUND_DESCRIPTION}="HDMI1 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmiin-sound", ENV{SOUND_DESCRIPTION}="HDMI-In Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8316-sound", ENV{SOUND_DESCRIPTION}="ES8316 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}

# Mainline u-boot or Kwiboo's tree
function post_family_config_branch_edge__rock-5b_use_mainline_uboot() {
	display_alert "$BOARD" "mainline (next branch) u-boot overrides for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="rock5b-rk3588_defconfig"                       # override the default for the board/family
	declare -g BOOTDELAY=1                                                # Wait for UART interrupt to enter UMS/RockUSB mode etc
	declare -g BOOTSOURCE="https://github.com/Kwiboo/u-boot-rockchip.git" # We ❤️ Kwiboo's tree
	declare -g BOOTBRANCH="branch:rk3xxx-2024.04"                         # commit:31522fe7b3c7733313e1c5eb4e340487f6000196 as of 2024-04-01
	declare -g BOOTPATCHDIR="v2024.04-rock5b-radxa"                       # empty; defconfig changes are done in hook below
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

function post_config_uboot_target__extra_configs_for_rock5b_mainline_environment_in_spi() {
	[[ "${BRANCH}" != "edge" ]] && return 0

	display_alert "$BOARD" "u-boot configs for ${BOOTBRANCH} u-boot config BRANCH=${BRANCH}" "info"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_IS_NOWHERE "n"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_IS_IN_SPI_FLASH "y"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_SECT_SIZE_AUTO "y"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_OVERWRITE "y"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_SIZE "0x20000"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_OFFSET "0xc00000"
}

# Include fw_setenv, configured to point to the correct spot on the SPI Flash
PACKAGE_LIST_BOARD="libubootenv-tool" # libubootenv-tool provides fw_printenv and fw_setenv, for talking to U-Boot environment
function post_family_tweaks__config_rock5b_fwenv() {
	[[ "${BRANCH}" != "edge" ]] && return 0
	display_alert "Configuring fw_printenv and fw_setenv" "for ${BOARD} and u-boot ${BOOTBRANCH}" "info"
	# Addresses below come from CONFIG_ENV_OFFSET and CONFIG_ENV_SIZE in defconfig
	cat <<- 'FW_ENV_CONFIG' > "${SDCARD}"/etc/fw_env.config
		# MTD/SPI u-boot env for the Rock-5b
		# MTD device name Device offset Env. size Flash sector size Number of sectors
		/dev/mtd0         0xc00000      0x20000
	FW_ENV_CONFIG
}
