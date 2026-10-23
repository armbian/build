# Rockchip RK3399 hexa core 4GB RAM SoC GBE eMMC USB3 USB-C WiFi/BT
BOARD_NAME="Orange Pi 4"
BOARD_VENDOR="xunlong"
BOARDFAMILY="rockchip64" # Used to be rk3399
BOARD_MAINTAINER="paolosabatino"
INTRODUCED="2019"
BOOTCONFIG="orangepi-4-rk3399_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
ASOUND_STATE="asound.state.rt5651"
BOOT_LOGO="desktop"
BOOTBRANCH_BOARD="tag:v2026.10"
BOOTPATCHDIR="v2026.10"
BOOT_SCENARIO="binman-atf-mainline"
DDR_BLOB="rk33/rk3399_ddr_933MHz_v1.30.bin"

function post_family_config__orangepi4_atf() {
	display_alert "$BOARD" "u-boot: TF-A lts-v2.14.11" "info"
	declare -g ATFSOURCE="https://git.trustedfirmware.org/TF-A/trusted-firmware-a.git"
	declare -g ATFBRANCH="tag:lts-v2.14.11"
	declare -g ATFPATCHDIR="atf-rockchip64/v2.14"
}

function post_config_uboot_target__orangepi4_features() {
	display_alert "$BOARD" "u-boot: enable network boot, storage and debug commands" "info"
	local opt
	for opt in CMD_DHCP CMD_PING CMD_PXE CMD_TFTPBOOT CMD_NFS CMD_WGET CMD_DNS \
		ROCKCHIP_EFUSE MISC_INIT_R CMD_PCI CMD_NVME CMD_SCSI CMD_EXT4_WRITE FAT_WRITE \
		CMD_GPIO CMD_I2C CMD_PMIC CMD_REGULATOR CMD_POWEROFF \
		DM_RNG RNG_ROCKCHIP CMD_RNG CMD_KASLRSEED CMD_HASH CMD_BOOTMENU CMD_EFICONFIG; do
		run_host_command_logged scripts/config --enable "CONFIG_${opt}"
	done
}

