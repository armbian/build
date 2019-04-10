# H3/H2+ quad core 512MB SoC Wi-Fi/BT
BOARD_NAME="Banana Pi M2 Zero"
BOARDFAMILY="sun8i"
BOOTCONFIG="bananapi_m2_zero_defconfig"
#
MODULES="#w1-sunxi #w1-gpio #w1-therm #sunxi-cir dhd hci_uart rfcomm hidp"
MODULES_NEXT="brcmfmac g_serial"
#
KERNEL_TARGET="default,next,dev"
CLI_TARGET=""
DESKTOP_TARGET=""
#
CLI_BETA_TARGET=""
DESKTOP_BETA_TARGET=""
