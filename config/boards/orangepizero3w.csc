# Allwinner A733 octa core 4-16GB RAM WiFi6/BT UFS/eMMC microSD
BOARD_NAME="Orange Pi Zero 3W"
INTRODUCED="2025"
BOOT_FDT_FILE="allwinner/sun60i-a733-orangepi-zero3w.dtb"
SUNXI_BOOT0_SDCARD_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_sdcard_orangepizero3w.fex"
SUNXI_BOOT0_SPINOR_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_sdcard_orangepizero3w.fex"
BOARD_MAINTAINER="shkolnik"

source "${SRC}/config/sources/vendors/xunlong/sun60iw2-a733-common.inc"
