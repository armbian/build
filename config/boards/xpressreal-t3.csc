# Realtek rtd1619b quad core 4GB Mem/32GB eMMC 1x HDMI 1x USB 3.2 1x USB 2.0
BOARD_NAME="XpressReal T3"
BOARDFAMILY="realtek-rtd1619b"
KERNEL_TARGET="vendor"
DEFAULT_CONSOLE="both"
SERIALCON="ttyS0:460800"
FULL_DESKTOP="yes"
BOOT_FDT_FILE="realtek/rtd1619b-bleedingedge-4gb.dtb"

ROOTFS_TYPE="ext4"
ROOT_FS_LABEL="ROOT"

BOOTFS_TYPE="fat"
BOOT_FS_LABEL="BOOT"
BOOTSIZE=512

declare -g BLUETOOTH_HCIATTACH_PARAMS="/dev/ttyS1 any 1500000 flow"
enable_extension "bluetooth-hciattach"
