# MBa8MPxL with TQMa8MPxL
BOARD_NAME="MBa8MPxL"
BOARDFAMILY="imx8m"
BOARD_MAINTAINER="schmiedelm"
HAS_VIDEO_OUTPUT="yes"
ATF_PLAT="imx8mp"
ATF_UART_BASE="0x30a60000"
BOOTCONFIG="tqma8mpxl_multi_mba8mpxl_defconfig"
KERNEL_TARGET="current"
DEFAULT_CONSOLE="serial"
SERIALCON="ttymxc3"
BOOT_FDT_FILE="freescale/imx8mp-tqma8mpql-mba8mpxl.dtb"
ASOUND_STATE="asound.state.tqma"

function post_family_tweaks_bsp__mba8mpxl() {
	mkdir -p "$destination"/etc/X11/xorg.conf.d
	cat <<- EOF > "$destination"/etc/X11/xorg.conf.d/02-driver.conf
		Section "Device"
		Identifier              "main"
		driver                  "fbdev"
		Option                  "fbdev" "/dev/fb0"
		EndSection
	EOF
}
