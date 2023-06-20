# TI AM64 dual core 2GB 2xGBE USB3 WiFi OSPI

BOARD_NAME="SK-AM64B"
BOARDFAMILY="k3"
BOARD_MAINTAINER="glneo"
BOOTCONFIG="am64x_evm_a53_defconfig"
BOOTFS_TYPE="fat"
BOOT_FDT_FILE="ti/k3-am642-sk.dts"
BOOTSCRIPT="boot-sk-am64b.cmd:uEnv.txt"
TIBOOT3_FILE="tiboot3-am64x_sr2-hs-fs-evm.bin"
DEFAULT_CONSOLE="serial"
HAS_VIDEO_OUTPUT="no"
KERNEL_TARGET="current,edge"
SERIALCON="ttyS2"
