# Rockchip RK3568 quad core 1-8GB SoC GBe eMMC USB3
BOARD_NAME="100ASK DshanPi R1 / R1+"
BOARD_VENDOR="dongshanpi"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
INTRODUCED="2024"
BOOTCONFIG="dshanpi-r1-rk3568_defconfig"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3568-dshanpi-r1.dtb"
BOOT_SCENARIO="binman"
IMAGE_PARTITION_TABLE="gpt"

# Put the serial console after HDMI tty1.
# /dev/console then stays on the debug UART.
function dshanpi_r1_serial_console_last() {
	# SRC_EXTLINUX=yes ships no boot.cmd.
	[[ $SRC_EXTLINUX == yes ]] && return 0
	local boot_cmd="$1"
	local serial_console="ttyS2,1500000"
	[[ $BRANCH == vendor ]] && serial_console="ttyFIQ0,1500000"
	display_alert "$BOARD" "Putting console=${serial_console%%,*} last in ${boot_cmd}" "info"
	if ! grep -qF 'setenv consoleargs "console=ttyS2,1500000 ${consoleargs}"' "${boot_cmd}"; then
		exit_with_error "dshanpi-r1: boot.cmd console template changed; update the sed in dshanpi_r1_serial_console_last"
	fi
	sed -i "s/setenv consoleargs \"console=ttyS2,1500000 \${consoleargs}\"/setenv consoleargs \"\${consoleargs} console=${serial_console}\"/" \
		"${boot_cmd}"
}

function post_family_tweaks__dshanpi-r1_serial_console_last() {
	dshanpi_r1_serial_console_last "${SDCARD}/boot/boot.cmd"
}

# The BSP postinst copies this boot.cmd to /boot.
function post_family_tweaks_bsp__dshanpi-r1_serial_console_last() {
	dshanpi_r1_serial_console_last "${destination}/usr/share/armbian/boot.cmd"
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
