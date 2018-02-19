# H3/H2+ quad core 512MB SoC Wi-Fi/BT
BOARD_NAME="Banana Pi M2 Zero"
BOARDFAMILY="sun8i"
BOOTCONFIG="Sinovoip_BPI_M2_Zero_defconfig"
#
MODULES="#w1-sunxi #w1-gpio #w1-therm #sunxi-cir dhd hci_uart rfcomm hidp"
MODULES_NEXT="brcmfmac g_serial"
CPUMIN="240000"
CPUMAX="1200000"
#
KERNEL_TARGET="default,next,dev"
CLI_TARGET=""
DESKTOP_TARGET=""
#
CLI_BETA_TARGET="stretch:next"
DESKTOP_BETA_TARGET=""
#
RECOMMENDED="Debian_stretch_next_nightly:75"
#
BOARDRATING=""
CHIP="http://docs.armbian.com/Hardware_Allwinner-H3/"
REVIEW="https://forum.armbian.com/topic/4801-banana-pi-zero/"
HARDWARE="https://linux-sunxi.org/Sinovoip_Banana_Pi_M2_Zero"
FORUMS="http://forum.armbian.com/index.php/forum/13-allwinner-h3/"
BUY="http://amzn.to/2Hi9DVt"
