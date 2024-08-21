# Rockchip RK3399Pro hexa core NPU 4GB SoC GBe eMMC USB3 PCIe WiFi/BT
BOARD_NAME="Tinker Edge R"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
BOOTCONFIG="tinker-edge-r_rk3399pro_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399pro-tinker-edge-r.dtb"
BOOT_SUPPORT_SPI=yes
BOOT_SCENARIO="tpl-spl-blob"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200 console=tty1"
