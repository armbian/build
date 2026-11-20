# Allwinner Cortex-A55 octa core 2/4GB RAM SoC USB3 USB-C 2x GbE LCD
BOARD_NAME="Avaota A1"
BOARD_VENDOR="yuzukihd"
BOARDFAMILY="sun55iw3"
BOARD_MAINTAINER="juanesf"
INTRODUCED="2024"
BOOTCONFIG="avaota-a1_defconfig"
OVERLAY_PREFIX="sun55i-t527"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"
BOOT_FDT_FILE="allwinner/sun55i-t527-avaota-a1.dtb"
HAS_VIDEO_OUTPUT="yes"

# GPT is overwritten by the eGON bootloader image at 8 KiB (issue #10647)
IMAGE_PARTITION_TABLE="msdos"
BOOTFS_TYPE="fat"

PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"

# AIC8800D80 WiFi on SDIO, Bluetooth on UART
AIC8800_TYPE="sdio"
AIC8800_SDIO_BT="yes"
AIC8800_MODPROBE_OPTIONS="options aic8800_fdrv_sdio aicwf_dbg_level=0 custregd=0 ps_on=0"
enable_extension "radxa-aic8800"
