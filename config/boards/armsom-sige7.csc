# Rockchip RK3588 SoC octa core 8-64GB SoC 2*2.5GBe eMMC USB3 NvME WIFI
BOARD_NAME="ArmSoM Sige7"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="armsom-sige7-rk3588_defconfig"
KERNEL_TARGET="current,edge,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588-armsom-sige7.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"
IMAGE_PARTITION_TABLE="gpt"

# @TODO: consider removing those, as the defaults in rockchip64_common have been bumped up
DDR_BLOB='rk35/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.11.bin'
BL31_BLOB='rk35/rk3588_bl31_v1.38.elf'

function post_family_tweaks__armsom-sige7_naming_audios() {
	display_alert "$BOARD" "Renaming armsom-sige7 audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8316-sound", ENV{SOUND_DESCRIPTION}="ES8316 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}
