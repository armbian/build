# Rockchip RK3588 octa core 4-32GB RAM SoC eMMC NVMe SATA USB3 GbE 2x HDMI DP
BOARD_NAME="Youyeetoo YY3588"
BOARD_VENDOR="youyeetoo"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="SuperKali"
BOOTCONFIG="youyeetoo-yy3588-rk3588_defconfig"
BOOT_SOC="rk3588"
KERNEL_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_FDT_FILE="rockchip/rk3588-youyeetoo-yy3588.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"

function post_family_tweaks__youyeetoo_yy3588_naming_audios() {
	display_alert "$BOARD" "Renaming Youyeetoo YY3588 audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmiin-sound", ENV{SOUND_DESCRIPTION}="HDMI-In Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8323-sound", ENV{SOUND_DESCRIPTION}="ES8323 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}
