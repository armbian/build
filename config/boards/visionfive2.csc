# RISC-V StarFive Visionfive V2
BOARD_NAME="VisionFive2"
BOARD_VENDOR="star-five"
BOARDFAMILY="starfive2"
BOARD_MAINTAINER="libiunc"
INTRODUCED="2023"
KERNEL_TARGET="vendor"
BOOT_FDT_FILE="starfive/jh7110-starfive-visionfive-2-v1.3b.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n8 console=tty0 earlycon=sbi rootflags=data=writeback stmmaceth=chain_mode:1 rw"
BOOTCONFIG=none

function post_family_tweaks__visionfive2_uenv() {
	# rpardini: uEnv.txt is broken on modern SPI u-boot, disabling it
	display_alert "$BOARD" "skipping uEnv.txt generation for modern U-Boot compatibility" "info"
	return 0
}

function post_assign_board_extlinux_paths() {
	# Force correct root symlinks for single ext4 partition on StarFive
	KERNEL_PATH="/vmlinuz"
	INITRD_PATH="/initrd.img"
	FDT_PATH="/boot/starfive/jh7110-starfive-visionfive-2-v1.3b.dtb"
}
