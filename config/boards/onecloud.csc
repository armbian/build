# Amlogic S805 quad core 1GB RAM SoC GBE
BOARD_NAME="OneCloud"
BOARDFAMILY="meson8b"
KERNEL_TARGET="current,edge"

BOOTCONFIG="none"
BOOTSCRIPT="boot-onecloud.cmd:boot.cmd"
BOOTENV_FILE="onecloud.txt"

OFFSET="16"
BOOTSIZE="256"
BOOTFS_TYPE="fat"

# ROOTFS_TYPE="f2fs"
# FIXED_IMAGE_SIZE=7456

BOOT_LOGO=desktop
