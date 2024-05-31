# Rockchip RK3588s SoC octa core 4-16GB SoC eMMC USB3 NvME
BOARD_NAME="Rock 5C"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="rock-5c-rk3588s_defconfig"
KERNEL_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-rock-5c.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SOC="rk3588"
IMAGE_PARTITION_TABLE="gpt"
enable_extension "radxa-aic8800"
AIC8800_TYPE="usb"

function post_family_config__uboot_rock5c() {
        display_alert "$BOARD" "Configuring armsom u-boot" "info"
        declare -g BOOTSOURCE='https://github.com/radxa/u-boot.git'
        declare -g BOOTBRANCH="branch:next-dev-v2024.03"
        declare -g OVERLAY_PREFIX='rockchip-rk3588'
	declare -g BOOTDELAY=1   # build injects this into u-boot config. we can then get into UMS mode and avoid the whole rockusb/rkdeveloptool thing
}

function post_family_tweaks__rock5c_naming_audios() {
	display_alert "$BOARD" "Renaming rock5c audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8316-sound", ENV{SOUND_DESCRIPTION}="ES8316 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}

function post_family_tweaks__rock5c_naming_wireless_interface() {
	display_alert "$BOARD" "Renaming rock5c wifi" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="88:00:*", NAME="$ENV{ID_NET_SLOT}"' > $SDCARD/etc/udev/rules.d/99-radxa-aic8800.rules

	return 0
}
