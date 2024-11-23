# SpacemiT K1 octa core RISC-V SoC 2GB/4GB RAM 8GB/16GB eMMC 4x USB3 2x GbE
BOARD_NAME="Banana Pi F3"
BOARDFAMILY="spacemit"
BOARD_MAINTAINER=""
KERNEL_TARGET="legacy,current"
KERNEL_TEST_TARGET="legacy"
BOOT_FDT_FILE="spacemit/k1-bananapi-f3.dtb"
BOOTDELAY=1
SRC_EXTLINUX="yes"
SRC_CMDLINE="earlycon=sbi console=tty1 console=ttyS0,115200 clk_ignore_unused swiotlb=65536"
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"

function post_config_uboot_target__extra_configs_for_bananapi_f3() {
	display_alert "u-boot for ${BOARD}" "u-boot: enabling extra configs" "info"

	run_host_command_logged scripts/config --enable CONFIG_SD_BOOT
	run_host_command_logged scripts/config --enable CONFIG_EXT4_WRITE
	run_host_command_logged scripts/config --enable CONFIG_FS_BTRFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_BTRFS
}

function post_family_tweaks_bsp__bananapi_f3_extras() {
	if [[ -d "$SRC/packages/blobs/riscv64/spacemit" ]]; then
		run_host_command_logged mkdir -pv "${destination}"/lib/firmware
		display_alert "$BOARD" "Installing boot firmware" "info"
		run_host_command_logged cp -fv $SRC/packages/blobs/riscv64/spacemit/esos.elf "${destination}"/lib/firmware
	fi

	display_alert "$BOARD" "Force load wireless" "info"

	run_host_command_logged mkdir -pv "${destination}"/etc/modules-load.d
	run_host_command_logged echo "8852bs" > "${destination}"/etc/modules-load.d/${BOARD}.conf
}
