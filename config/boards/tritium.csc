# H3 quad core 512MB/1Gb/2Gb SoC eMMC
BOARD_NAME="Tritium"
BOARDFAMILY="sun8i"
BOOTCONFIG="librecomputer_tritium_defconfig"
#
MODULES="#w1-sunxi #w1-gpio #w1-therm #sunxi-cir hci_uart rfcomm hidp dhd g_serial"
MODULES_NEXT="g_serial"
DEFAULT_OVERLAYS="usbhost1 usbhost2"
CPUMIN="240000"
CPUMAX="912000"
#
KERNEL_TARGET="next"
CLI_TARGET=""

CLI_BETA_TARGET=""
#
RECOMMENDED=""
#
BOARDRATING=""
CHIP="http://docs.armbian.com/Hardware_Allwinner-H3/"
HARDWARE="https://libre.computer/products/boards/all-h3-cc/"
FORUMS="http://forum.armbian.com/index.php/forum/13-allwinner-h3/"
MISC3="<a href=http://forum.armbian.com/index.php/topic/1614-running-h3-boards-with-minimal-consumption/>Minimize consumption</a>"
BUY=""
