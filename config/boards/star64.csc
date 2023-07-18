# RISC-V Pine64 Star64
BOARD_NAME="Star64"
BOARDFAMILY="starfive2"
BOARD_MAINTAINER=""
KERNEL_TARGET="edge"
BOOT_FDT_FILE="starfive/jh7110-star64-pine64.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n8 console=tty0 earlycon=sbi rootflags=data=writeback stmmaceth=chain_mode:1 rw"
BOOTCONFIG=none

function post_family_tweaks__star64_uenv() {
	# rpardini: uEnv.txt is needed to re-enable distroboot-like behaviour on the board's SPI u-boot
	display_alert "$BOARD" "creating uEnv.txt" "info"
	cat <<- UENV_SCRIPT_HEADER > "${SDCARD}/boot/uEnv.txt"
		fdt_high=0xffffffffffffffff
		initrd_high=0xffffffffffffffff

		kernel_addr_r=0x44000000
		kernel_comp_addr_r=0x90000000
		kernel_comp_size=0x10000000

		fdt_addr_r=0x48000000
		ramdisk_addr_r=0x48100000

		# Move distro to first boot to speed up booting
		boot_targets=distro mmc1 dhcp 

		distro_bootpart=1

		# Fix missing bootcmd
		bootcmd=run bootcmd_distro
	UENV_SCRIPT_HEADER

	return 0
}
