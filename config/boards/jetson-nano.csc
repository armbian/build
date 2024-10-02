# Nvidia Jetson Nano quad core 2G/4GB SoC 4 x USB3 HDMI & DP
declare -g BOARD_NAME="Jetson Nano"
declare -g BOARDFAMILY="uefi-arm64"
declare -g BOARD_MAINTAINER=""
declare -g KERNEL_TARGET="current,edge"
declare -g KERNEL_TEST_TARGET="current"

declare -g BOOT_LOGO=desktop

declare -g GRUB_CMDLINE_LINUX_DEFAULT="efi=noruntime console=ttyS0,115200n8"
declare -g BOOT_FDT_FILE="nvidia/tegra210-p3450-0000.dtb"
enable_extension "grub-with-dtb"
