# Rockchip RK3399 hexa core 2GB SoC GBe eMMC USB3 WiFi/BT
BOARD_NAME="Tinker Board 2"
BOARD_VENDOR="asus"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
INTRODUCED="2021"
BOOTCONFIG="tinker-2-rk3399_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-tinker-2.dtb"
SERIALCON="ttyS2"
BOARD_FIRMWARE_INSTALL="-full" # Install full firmware, for rtl8822ce firmware and others
BOOTBRANCH_BOARD="tag:v2026.10"
BOOTPATCHDIR="v2026.10"
BOOT_SCENARIO="binman-atf-mainline"
DDR_BLOB="rk33/rk3399_ddr_800MHz_v1.27.bin" # Different blob for TB2

function post_family_config__tinkerboard2_atf() {
	display_alert "$BOARD" "u-boot: TF-A lts-v2.14.11" "info"
	declare -g ATFSOURCE="https://git.trustedfirmware.org/TF-A/trusted-firmware-a.git"
	declare -g ATFBRANCH="tag:lts-v2.14.11"
	declare -g ATFPATCHDIR="atf-rockchip64/v2.14"
}

function post_config_uboot_target__tinkerboard2_features() {
	display_alert "$BOARD" "u-boot: enable network boot, storage and debug commands" "info"
	local opt
	for opt in CMD_DHCP CMD_PING CMD_PXE CMD_TFTPBOOT CMD_NFS CMD_WGET CMD_DNS \
		ROCKCHIP_EFUSE MISC_INIT_R CMD_NVME CMD_SCSI CMD_EXT4_WRITE FAT_WRITE \
		CMD_GPIO CMD_I2C CMD_PMIC CMD_REGULATOR CMD_POWEROFF \
		DM_RNG RNG_ROCKCHIP CMD_RNG CMD_KASLRSEED CMD_HASH CMD_BOOTMENU CMD_EFICONFIG; do
		run_host_command_logged scripts/config --enable "CONFIG_${opt}"
	done
}
