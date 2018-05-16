# H5 quad core 2Gb SoC eMMC
BOARD_NAME="Tritium"
BOARDFAMILY="sun50iw2"
BOOTCONFIG="libretech_all_h3_cc_h5_defconfig"
#
MODULES="#w1-sunxi #w1-gpio #w1-therm #sunxi-cir hci_uart rfcomm hidp dhd"
MODULES_NEXT=""
DEFAULT_OVERLAYS=""
CPUMIN="240000"
CPUMAX="1200000"
#
KERNEL_TARGET="next"
CLI_TARGET=""

CLI_BETA_TARGET=""
#
RECOMMENDED="Ubuntu_xenial_next_nightly:75"
#
BOARDRATING=""
CHIP="http://docs.armbian.com/Hardware_Allwinner-H3/"
HARDWARE="https://libre.computer/products/boards/all-h3-cc/"
FORUMS="http://forum.armbian.com/index.php/forum/13-allwinner-h3/"
MISC3="<a href=http://forum.armbian.com/index.php/topic/1614-running-h3-boards-with-minimal-consumption/>Minimize consumption</a>"
BUY=""
