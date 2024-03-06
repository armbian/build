# x86_64 via UEFI/BIOS for generic virtual board
#
# Usage: Use this board to run armbian on a
#        virtualized environment (eg: QEMU/KVM)
#
# Notes:
# - Differences with the 'uefi-x86' board:
#   - support kernel boot messages on graphical
#     and console/serial devices
#   - support prompt on graphical/console devices
#   - Patches targeting virtualized env on x86
#     should be added here - when it make sense :)
#
declare -g BOARD_NAME="UEFI x86 (QEMU)"
declare -g BOARDFAMILY="uefi-x86"
declare -g BOARD_MAINTAINER="davidandreoletti"
declare -g KERNEL_TARGET="legacy,current,edge"
declare -g SERIALCON="tty1,ttyS0"

declare -g BOOT_LOGO=desktop

declare -g GRUB_CMDLINE_LINUX_DEFAULT="earlyprintk=ttyS0,115200,keep"
declare -g DEFAULT_CONSOLE="both"
declare -g UEFI_GRUB_TERMINAL="gfxterm vga_text console serial"
