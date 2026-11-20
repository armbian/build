# Allwinner T527 octa core 2/4GB RAM eMMC NVMe GBE WiFi/BT HDMI 4x USB2
BOARD_NAME="Orange Pi 4A"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun55iw3"
BOARD_MAINTAINER=""
INTRODUCED="2025"
BOOTCONFIG="orangepi_4a_defconfig"
OVERLAY_PREFIX="sun55i-t527"
KERNEL_TARGET="edge"
BOOT_FDT_FILE="sun55i-t527-orangepi-4a.dtb"

# GPT is overwritten by the eGON bootloader image at 8 KiB (issue #10647)
IMAGE_PARTITION_TABLE="msdos"
BOOTFS_TYPE="fat"
