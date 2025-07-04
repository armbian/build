# Allwinner Cortex-A55 octa-core 2/4GB SoC SPI SD eMMC NVMe GBe HDMI
BOARD_NAME="Orange Pi 4A"
BOARDFAMILY="sun55iw3"
BOARD_MAINTAINER=""
BOOTCONFIG="sun55iw3p1_t527_defconfig" #fixme
OVERLAY_PREFIX="sun55i-t527" #fixme
#BOOT_LOGO="desktop"
KERNEL_TARGET="dev,edge"
BOOT_FDT_FILE="dtb/allwinner/sun55i-t527-orangepi-4a.dtb" #fixme
IMAGE_PARTITION_TABLE="gpt"
#IMAGE_PARTITION_TABLE="msdos"
BOOTFS_TYPE="fat"
BOOTSTART="1"
BOOTSIZE="512"
ROOTSTART="513"

