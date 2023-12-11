# Kirin 960 octa core 3/4GB SoC eMMC USB3 WiFi/BT
declare -g BOARD_NAME="HiKey 960"
declare -g BOARDFAMILY="uefi-arm64"
declare -g BOARD_MAINTAINER=""
declare -g KERNEL_TARGET="current,edge"

declare -g GRUB_CMDLINE_LINUX_DEFAULT="efi=noruntime console=ttyAMA6,115200n8"
declare -g BOOT_FDT_FILE="hisilicon/hi3660-hikey960.dtb"
enable_extension "grub-with-dtb"
