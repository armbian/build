# Allwinner H3 quad core 1GB RAM WiFi eMMC
BOARD_NAME="Orange Pi PC +"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun8i"
BOARD_MAINTAINER="Janmcha"
INTRODUCED="2016"
BOOTCONFIG="orangepi_pc_plus_defconfig"
BOOTBRANCH="tag:v2026.10"
BOOTPATCHDIR="v2026.10-sunxi"
# Crust orangepi_pc_plus_defconfig does not resume from suspend; use the generic config.
CRUSTCONFIG="h3_defconfig"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="current"
