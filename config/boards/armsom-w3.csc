# Rockchip RK3588 SoC octa core 8-32GB SoC 2.5GBe PoE eMMC USB3 NvME
BOARD_NAME="ArmSoM W3"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="armsom-w3-rk3588_defconfig"
KERNEL_TARGET="legacy"
KERNEL_TEST_TARGET="legacy" # in case different then kernel target
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588-armsom-w3.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"
IMAGE_PARTITION_TABLE="gpt"
SKIP_BOOTSPLASH="yes" # Skip boot splash patch, conflicts with CONFIG_VT=yes
BOOTFS_TYPE="ext4"
DDR_BLOB='rk35/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.11.bin'
BL31_BLOB='rk35/rk3588_bl31_v1.38.elf'

# post_family_config hook which only runs when branch is legacy.
function post_family_config_branch_legacy__uboot_armsom() {
	display_alert "$BOARD" "Configuring armsom u-boot" "info"
	declare -g BOOTSOURCE='https://github.com/radxa/u-boot.git'
	declare -g BOOTBRANCH="commit:b54d452d46459bc6e4cfc1a2795c9aad143aa174" # specific commit in next-dev branch
	declare -g OVERLAY_PREFIX='rockchip-rk3588'
	declare -g BOOTDIR="u-boot-${BOARD}"                  # do not share u-boot directory
	declare -g BOOTPATCHDIR="legacy/u-boot-armsom-rk3588" # Few patches in there; defconfig & DT
	declare -g BOOTDELAY=1                                # build injects this into u-boot config. we can then get into UMS mode and avoid the whole rockusb/rkdeveloptool thing
}

function post_family_tweaks__armsom-w3_naming_audios() {
	display_alert "$BOARD" "Renaming armsom-w3 audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi1-sound", ENV{SOUND_DESCRIPTION}="HDMI1 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmiin-sound", ENV{SOUND_DESCRIPTION}="HDMI-In Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8316-sound", ENV{SOUND_DESCRIPTION}="ES8316 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}
