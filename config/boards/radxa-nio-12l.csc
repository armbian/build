# Mediatek MT8395 quad core 4GB 8GB 16GB
BOARD_NAME="Radxa Nio 12L"
BOARDFAMILY="genio"
BOARD_MAINTAINER="HeyMeco"
KERNEL_TARGET="collabora"
KERNEL_TEST_TARGET="collabora"
declare -g BOOT_FDT_FILE="mediatek/mt8395-radxa-nio-12l.dtb" #declare needed else the extension looks for DT without .dtb
enable_extension "grub-with-dtb"
HAS_VIDEO_OUTPUT="yes"
INSTALL_ARMBIAN_FIRMWARE="full"
declare -g BOARD_FIRMWARE_INSTALL="-full"

