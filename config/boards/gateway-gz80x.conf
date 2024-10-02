# Amlogic A113X quad core 1Gb RAM SoC, eMMC 8Gb
BOARD_NAME="Gateway GZ80x"
BOARDFAMILY="meson-axg"
BOARD_MAINTAINER="pyavitz"
BOOTCONFIG="amper_gateway_am-gz80x_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
BOOTBRANCH_BOARD="tag:v2024.07"
BOOTPATCHDIR="v2024.07"
BOOT_FDT_FILE="amlogic/meson-axg-amper-gateway-am-gz80x.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyAML0,115200n8 clk_ignore_unused loglevel=7"
HAS_VIDEO_OUTPUT="no"

function post_family_tweaks_bsp__gateway_gz80x_udev() {
	mkdir -p "${destination}"/etc/udev/rules.d
	display_alert "$BOARD" "Install zwave udev rule" "info"
	echo 'KERNEL=="ttyAML2", NAME="tts/%n", SYMLINK+="zwave", GROUP="dialout", MODE="0660"' > "${destination}"/etc/udev/rules.d/10-zwave.rules
}
