# H3 quad core 512MB/1Gb/2Gb SoC eMMC
BOARD_NAME="Tritium"
BOARDFAMILY="sun8i"
BOOTCONFIG="libretech_all_h3_cc_h3_defconfig"
#
MODULES="#w1-sunxi #w1-gpio #w1-therm #sunxi-cir hci_uart rfcomm hidp dhd g_serial"
MODULES_NEXT="g_serial"
DEFAULT_OVERLAYS="usbhost1 usbhost2"
CPUMIN="240000"
CPUMAX="912000"
#
KERNEL_TARGET="next,dev"
CLI_TARGET="stretch,bionic:next"
DESKTOP_TARGET=""
