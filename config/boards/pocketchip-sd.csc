# Allwinner R8(A13) single core 512Mb (NextThing C.H.I.P.) with MMC2 breakout
BOARD_NAME="NextThing C.H.I.P."
BOARDFAMILY="sun5i"
BOARD_MAINTAINER="TheSnowfield"
HAS_VIDEO_OUTPUT="yes"
BOOTCONFIG="CHIP_defconfig"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
BOOTSCRIPT="boot-sunxi-pocketchip-sd.cmd:boot.cmd"
