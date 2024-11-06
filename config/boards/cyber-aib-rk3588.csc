# Rockchip RK3588 octa core 8/16GB RAM SoC 64/128GB eMMC NVMe 1x USB3 1x USB-C 2x 2.5GbE 2x HDMI
BOARD_NAME="Cyber Aib RK3588"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="rk3588-cyber-aib_defconfig"
KERNEL_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588-cyber-aib.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SOC="rk3588"
IMAGE_PARTITION_TABLE="gpt"

function post_family_tweaks__cyberaib_naming_audios() {
	display_alert "$BOARD" "Renaming cyber-aib audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmiin-sound", ENV{SOUND_DESCRIPTION}="HDMI-In Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}
