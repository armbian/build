# Rockchip RK3588S octa core 4/8/16GB RAM SoC compute module (3-port carrier: 1x GbE "wan", 2x 2.5GbE "lan1/lan2", 2x USB2 host, USB3/USB-C OTG, HDMI, SD, fan)
BOARD_NAME="Orange Pi CM5"
BOARD_VENDOR="xunlong"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
INTRODUCED="2024"
BOOTCONFIG="orangepi-5-rk3588s_defconfig" # CM5 has no dedicated mainline U-Boot defconfig; it's the same RK3588S SoC/DDR as the Orange Pi 5, whose defconfig is known to boot the CM5 fine
BOOT_SOC="rk3588"
KERNEL_TARGET="current,edge" # the CM5 device tree (backported into patch/kernel/archive/rockchip64-{6.18,7.2}/dt/) is only wired up for these two mainline-derived branches; the vendor/legacy BSP kernels don't carry it
KERNEL_TEST_TARGET="current,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-orangepi-cm5.dtb" # our own carrier dts (see patch/kernel/archive/.../dt/rk3588s-orangepi-cm5.dts), corrected against a dtb dumped off the reporter's actual booted vendor image; NOT the upstream "-base" board (rk3588s-orangepi-cm5-base.dtb), whose Ethernet PHY reset GPIO/timing and USB host wiring don't match this carrier
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"

# The CM5 module is the same RK3588S silicon/DDR as the Orange Pi 5, so reuse its known-working
# mainline U-Boot build (proven to boot the CM5 already, per user testing with the orangepi5 image).
# Only the kernel device tree (BOOT_FDT_FILE above) differs, since the CM5 Base Board carrier wires
# up different Ethernet PHYs (1x GbE + 2x PCIe 2.5GbE) than the Orange Pi 5 board.
function post_family_config__orangepicm5_use_mainline_uboot() {
	display_alert "$BOARD" "Mainline U-Boot overrides for $BOARD - $BRANCH" "info"

	declare -g BOOTCONFIG="orangepi-5-rk3588s_defconfig"
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.04"
	declare -g BOOTPATCHDIR="v2026.04"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB} $BOOTCONFIG;;u-boot-rockchip.bin u-boot-rockchip-spi.bin"
	unset uboot_custom_postprocess # disable stuff from rockchip64_common; we're using binman here which does all the work already
}

function post_family_tweaks__orangepicm5_naming_audios() {
	display_alert "$BOARD" "Renaming orangepi-cm5 audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}
