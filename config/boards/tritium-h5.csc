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
KERNEL_TARGET="next,dev"
CLI_TARGET="stretch,bionic:next"
DESKTOP_TARGET="bionic:next"
#
CLI_BETA_TARGET=""
#
DESKTOP_BETA_TARGET=""
