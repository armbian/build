# Allwinner A733 octa core 2-16GB RAM
BOARD_NAME="Orange Pi Zero 4"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun60iw2"
BOARD_MAINTAINER="JoshCodeStuff"
INTRODUCED="2026"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
IMAGE_PARTITION_TABLE="msdos"

BOOT_FDT_FILE="allwinner/sun60i-a733-orangepi-zero4.dtb"
SUNXI_BOOT0_SDCARD_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_sdcard_orangepizero4.fex"
SUNXI_BOOT0_SPINOR_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/boot0_sdcard_orangepizero4.fex"
SUNXI_SYS_CONFIG_FEX="${SRC}/packages/blobs/sunxi/sun60iw2/sys_config_orangepi.fex"

# AIC8800D80 combo: BT is UART HCI on ttyS1 and needs userspace bring-up
SUN60IW2_UART_BT="yes"

# Invalidate U-Boot cache if any of the blobs change
UBOOT_HASH_EXTRA="$(cat "${SUNXI_BOOT0_SDCARD_FEX}" "${SUNXI_BOOT0_SPINOR_FEX}" "${SUNXI_SYS_CONFIG_FEX}" | sha256sum | cut -d' ' -f1)"
