# RISC-V SiFive Unleashed
BOARD_NAME="Unleashed"
BOARDFAMILY="starfive"
BOARD_MAINTAINER=""
KERNEL_TARGET="edge"
BOOT_FDT_FILE="sifive/hifive-unleashed-a00.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n8 console=tty0 earlycon=sbi rootflags=data=writeback stmmaceth=chain_mode:1 rw"
BOOTCONFIG=none
