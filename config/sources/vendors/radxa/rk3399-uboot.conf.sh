#
# SPDX-License-Identifier: GPL-2.0
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/

# Shared U-Boot setup for the Radxa RK3399 boards: ROCK Pi 4A/4B/4B+/4C, ROCK 4C+, ROCK 4SE, ROCK Pi N10.
# SOURCED by the board files, so it has the same restrictions as a board file.
# Mainline U-Boot and TF-A, with the Rockchip DDR blob as TPL. Validated on ROCK Pi 4C (U-Boot) and ROCKPro64 (DDR blob TPL).
declare -g BOOTBRANCH_BOARD="tag:v2026.10"
declare -g BOOTPATCHDIR="v2026.10"
declare -g BOOT_SCENARIO="binman-atf-mainline"
# Newest Rockchip DDR blob (2023-04-17). A board file can set its own before sourcing this file.
declare -g DDR_BLOB="${DDR_BLOB:-"rk33/rk3399_ddr_933MHz_v1.30.bin"}"
enable_extension "uboot-btrfs"

function post_family_config__radxa_rk3399_uboot() {
	display_alert "$BOARD" "u-boot ${BOOTBRANCH_BOARD}, TF-A lts-v2.14.11, DDR blob TPL" "info"
	# The defconfigs put u-boot.itb at SPI offset 0xE0000; the generic rkspi_loader.img uses 0x60000.
	# Ship the binman SPI image instead, when the board boots from SPI.
	declare -g UBOOT_TARGET_MAP="BL31=bl31.elf ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin${BOOT_SUPPORT_SPI:+ u-boot-rockchip-spi.bin}"
	unset uboot_custom_postprocess
	declare -g ATFSOURCE="https://git.trustedfirmware.org/TF-A/trusted-firmware-a.git"
	declare -g ATFBRANCH="tag:lts-v2.14.11"
	declare -g ATFPATCHDIR="atf-rockchip64/v2.14"
	# RK3399Pro (ROCK Pi N10) runs the RK3399 TF-A platform; TF-A has no rk3399pro.
	declare -g ATF_TARGET_MAP="M0_CROSS_COMPILE=arm-linux-gnueabi- PLAT=rk3399 bl31;;build/rk3399/release/bl31/bl31.elf:bl31.elf"
}

function post_config_uboot_target__radxa_rk3399_features() {
	display_alert "$BOARD" "u-boot: DDR blob TPL, network boot, storage and debug commands" "info"
	# Rockchip DDR blob as TPL: on ROCKPro64 the mainline TPL fails LPDDR4 channel 0 after a warm reset.
	run_host_command_logged scripts/config --enable CONFIG_ROCKCHIP_EXTERNAL_TPL
	local opt
	for opt in CMD_DHCP CMD_PING CMD_PXE CMD_TFTPBOOT CMD_NFS CMD_WGET CMD_DNS \
		ROCKCHIP_EFUSE MISC_INIT_R \
		CMD_NVME CMD_SCSI CMD_SF CMD_MTD CMD_EXT4_WRITE FAT_WRITE \
		CMD_GPIO CMD_I2C CMD_PMIC CMD_REGULATOR CMD_LED CMD_POWEROFF \
		DM_RNG RNG_ROCKCHIP CMD_RNG CMD_KASLRSEED CMD_HASH CMD_BOOTMENU CMD_EFICONFIG; do
		run_host_command_logged scripts/config --enable "CONFIG_${opt}"
	done
	# ROCK Pi 4B and 4B+ build the shared rock-pi-4 defconfig (4A device tree). Point the default fdtfile at the board.
	[[ -n "${BOOT_FDT_FILE:-}" ]] && run_host_command_logged scripts/config --set-str DEFAULT_FDT_FILE "${BOOT_FDT_FILE}"
	return 0
}
