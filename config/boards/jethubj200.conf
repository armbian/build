# Amlogic S905X3 quad core 4GB RAM SoC eMMC GBE USB2 SPI-NOR
BOARD_NAME="JetHub D2"
BOARDFAMILY="jethub"
BOARD_MAINTAINER="adeepn"
BOOTCONFIG="jethub_j200_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
PACKAGE_LIST_BOARD="libubootenv-tool apparmor rfkill bluetooth bluez bluez-tools python3-pip watchdog"
[[ "${RELEASE}" == "jammy" ]] || PACKAGE_LIST_BOARD="${PACKAGE_LIST_BOARD} util-linux-extra"
MODULES_BLACKLIST="simpledrm" # SimpleDRM conflicts with Panfrost
FULL_DESKTOP="yes"
SERIALCON="ttyAML0"
#BOOT_LOGO="desktop"
