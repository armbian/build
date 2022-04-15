# Freescale / NXP iMx dual/quad core 1-2GB Gbe Wifi
BOARD_NAME="Udoo"
BOARDFAMILY="imx6"
BOOTCONFIG="udoo_defconfig"
KERNEL_TARGET="current,edge"
FULL_DESKTOP="yes"

BOARDCONFIG_BOOTBRANCH='tag:v2017.11'
BOARDCONFIG_SERIALCON=ttymxc1
BOARDCONFIG_BOOTSCRIPT="boot-udoo.cmd:boot.cmd"
BOARDCONFIG_BOOTENV_FILE='udoo.txt'
