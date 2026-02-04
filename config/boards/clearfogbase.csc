# Marvell Armada 38x dual core 1GB/2GB RAM SoC 1xmPCIe M.2 2xGBE SFP
BOARD_NAME="Clearfog Base"
BOARD_VENDOR="solidrun"
BOARDFAMILY="mvebu"
BOARD_MAINTAINER=""
BOOTCONFIG="clearfog_defconfig"
#BOOTCONFIG_EDGE="clearfogbase_defconfig"  # This had to be disabled because the clearfog is not yet ready for mainline uboot
HAS_VIDEO_OUTPUT="no"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
