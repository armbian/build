# Sophgo SG2000 T-Head C906 single core 512MB SoC headless 1x100MBe SD eMMC WiFi/BT USB2
BOARD_NAME="Milk-V Duo S (RISC-V)"
BOARD_VENDOR="milkv"
BOARDFAMILY="sophgo-sg200x-riscv64"
BOARD_MAINTAINER="lukaszsobala"
INTRODUCED="2024"
KERNEL_TARGET="edge,bleedingedge"
KERNEL_TEST_TARGET="edge"
BOOT_FDT_FILE="sophgo/sg2000-milkv-duo-s.dtb"
HAS_VIDEO_OUTPUT="no"

enable_extension "sophgo-sg200x-aic8800"
