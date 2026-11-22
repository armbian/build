# Allwinner A527 octa core 1/2/4GB RAM 0-32GB eMMC 2x GBE WiFi6/BT M.2 2230 NVMe/USB3 HDMI
BOARD_NAME="Cubie A5E"
BOARD_VENDOR="radxa"
BOARDFAMILY="sun55iw3"
BOARD_MAINTAINER="juanesf"
INTRODUCED="2025"
BOOTCONFIG="radxa-cubie-a5e_defconfig"
BOOT_SUPPORT_SPI="yes"
OVERLAY_PREFIX="sun55i-a527"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current,edge"
BOOT_FDT_FILE="sun55i-a527-cubie-a5e.dtb"
HAS_VIDEO_OUTPUT="yes"

# GPT is overwritten by the eGON bootloader image at 8 KiB (issue #10647)
IMAGE_PARTITION_TABLE="msdos"
BOOTFS_TYPE="fat"

PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools memtester"

# AIC8800D80 WiFi on SDIO, Bluetooth on UART
AIC8800_TYPE="sdio"
AIC8800_SDIO_BT="yes"
AIC8800_MODPROBE_OPTIONS="options aic8800_fdrv_sdio aicwf_dbg_level=0 custregd=0 ps_on=0"
enable_extension "radxa-aic8800"
