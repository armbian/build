# Rockchip RK3588S octa core 4/8/16GB RAM SoC NVMe USB3 USB-C GbE
BOARD_NAME="Retro Lite CM5"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="ginkage"
BOOT_SOC="rk3588"
BOOTCONFIG="retro-lite-cm5-rk3588s_defconfig"
KERNEL_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-retro-lite-cm5.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
DDR_BLOB="rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.16.bin"
BL31_BLOB="rk35/rk3588_bl31_v1.45.elf"

function post_family_tweaks__retrolitecm5_naming_audios() {
	display_alert "$BOARD" "Renaming Retro Lite CM5 audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-wm8960-sound", ENV{SOUND_DESCRIPTION}="WM8960 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}
