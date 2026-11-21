# Qualcomm SM8450 Snapdragon 8 Gen 1 octa core 8/12GB RAM 128/256/512GB UFS phone
# Generate kernel and rootfs image for Qcom ABL booting
declare -g BOARD_NAME="OnePlus 10 Pro"
declare -g BOARD_VENDOR="oneplus"
declare -g BOARDFAMILY="negroni"
declare -g INTRODUCED="2022"
declare -g KERNEL_TARGET="edge"
declare -g KERNEL_TEST_TARGET="edge"
declare -g BOOTCONFIG="none"
declare -g BOOT_FDT_FILE="qcom/sm8450-oneplus-negroni.dtb"
declare -g IMAGE_PARTITION_TABLE="gpt"
declare -g HAS_VIDEO_OUTPUT="no"
declare -g EXTRAWIFI="no"
declare -g INSTALL_ARMBIAN_FIRMWARE="no"
declare -g SERIALCON="ttyGS0"
declare -g PACKAGE_LIST_BOARD="busybox-static firmware-atheros iw lz4 wireless-regdb wpasupplicant"

declare -g EXTRA_BSPDEPS="mkbootimg, python3"
