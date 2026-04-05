# Dual-core Cortex-A35 + Cortex-M4, 512MB DDR
BOARD_NAME="NuMaker IoT MA35D16F90"
BOARD_VENDOR="nuvoton"
BOARDFAMILY="nuvoton-ma35d1"
# SD card boot (sdcard1 = SD1 slot on NuMaker IoT board)
BOOTCONFIG="ma35d1_sdcard1_defconfig"
KERNEL_TARGET="vendor"
FULL_DESKTOP="no"
BOOT_LOGO="no"
BOOT_FDT_FILE="nuvoton/ma35d1-iot-512m.dtb"
BOOT_SCENARIO="blobless"
IMAGE_PARTITION_TABLE="msdos"
DEFAULT_CONSOLE="serial"
SERIALCON="ttyS0:115200"

# Hardware features
HAS_VIDEO_OUTPUT="yes"
