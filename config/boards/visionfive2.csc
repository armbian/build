# RISC-V StarFive Visionfive V2
BOARD_NAME="VisionFive2"
BOARD_VENDOR="star-five"
BOARDFAMILY="starfive2"
BOARD_MAINTAINER="libiunc"
INTRODUCED="2023"
KERNEL_TARGET="vendor"
BOOT_FDT_FILE="starfive/jh7110-starfive-visionfive-2-v1.3b.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n8 console=tty0 earlycon=sbi rootflags=data=writeback stmmaceth=chain_mode:1 rw rw no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 splash plymouth.ignore-serial-consoles"
BOOTCONFIG=none

function post_assign_board_extlinux_paths() {
	KERNEL_PATH="/boot/Image"
	INITRD_PATH="/boot/uInitrd"
	FDT_PATH="/boot/dtb/${BOOT_FDT_FILE}"
}
