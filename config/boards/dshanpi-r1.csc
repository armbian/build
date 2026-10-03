# Rockchip RK3568 quad core 1-8GB SoC GBe eMMC USB3
BOARD_NAME="100ASK DshanPi R1 / R1+"
BOARD_VENDOR="dongshanpi"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
INTRODUCED="2024"
BOOTCONFIG="dshanpi-r1-rk3568_defconfig"
KERNEL_TARGET="current,edge,vendor"
KERNEL_TEST_TARGET="current,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3568-dshanpi-r1.dtb"
BOOT_SCENARIO="binman"
IMAGE_PARTITION_TABLE="gpt"
# vdd_cpu is a fixed 0.9 V rail.
# The CPU OPPs stop at 1.104 GHz.
CPUMAX="1104000"
# The R1+ M.2 E-key slot takes any WiFi card.
# Ship the full linux-firmware set.
BOARD_FIRMWARE_INSTALL="-full"

# The DTS enables WiFi and BT on SDMMC2 and UART8.
# The R1 has a soldered AP6256.
# The R1+ routes the same wiring to the M.2 E-key slot.
# PCIe cards in that slot leave the SDIO wiring unused.
# Use overlays=disable-pcie when both M.2 slots are empty.
# The overlay also disables any card in the E-key slot.
# An unused mainline PCIe PHY draws about 0.6 W.
# The overlay exists on current and edge kernels only.

function post_family_config__dshanpi-r1_overlay_prefix() {
	# The rk35xx family config sets OVERLAY_PREFIX to rk35xx.
	# The board prefix hides the overlays of other RK3568 boards.
	if [[ $BRANCH == current || $BRANCH == edge ]]; then
		declare -g OVERLAY_PREFIX="rockchip-rk3568-dshanpi-r1"
	fi
}

function post_family_tweaks__dshanpi-r1_serial_console_last() {
	# Put the serial console after HDMI tty1.
	# /dev/console then stays on the debug UART.
	local serial_console="ttyS2,1500000"
	[[ $BRANCH == legacy || $BRANCH == vendor ]] && serial_console="ttyFIQ0,1500000"
	display_alert "$BOARD" "Putting console=${serial_console%%,*} last in boot.cmd cmdline" "info"
	if ! grep -qF 'setenv consoleargs "console=ttyS2,1500000 ${consoleargs}"' "${SDCARD}/boot/boot.cmd"; then
		exit_with_error "dshanpi-r1: boot.cmd console template changed; update the sed in post_family_tweaks__dshanpi-r1_serial_console_last"
	fi
	sed -i "s/setenv consoleargs \"console=ttyS2,1500000 \${consoleargs}\"/setenv consoleargs \"\${consoleargs} console=${serial_console}\"/" \
		"${SDCARD}/boot/boot.cmd"
}

function post_family_config__dshanpi-r1_use_mainline_uboot() {
	display_alert "$BOARD" "Mainline U-Boot overrides for $BOARD - $BRANCH" "info"
	declare -g BOOTCONFIG="dshanpi-r1-rk3568_defconfig"
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot"
	declare -g BOOTBRANCH="tag:v2026.07"
	declare -g BOOTPATCHDIR="v2026.07"
	declare -g BOOTDIR="u-boot-${BOARD}"
}
