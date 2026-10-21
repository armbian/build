# Rockchip RK3399 hexa core 1-4GB SoC GBe eMMC USB3 WiFi/BT PoE miniDP USB host
BOARD_NAME="Rockpi 4C"
BOARD_VENDOR="radxa"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
INTRODUCED="2019"
BOOTBRANCH_BOARD="tag:v2026.10"
BOOTPATCHDIR="v2026.10"
BOOTCONFIG="rock-pi-4c-rk3399_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-rock-pi-4c.dtb"
BOOT_SCENARIO="binman-atf-mainline"
BOOT_SUPPORT_SPI=yes
enable_extension "uboot-btrfs"

# The defconfig puts u-boot.itb at SPI offset 0xE0000; the generic rkspi_loader.img
# uses 0x60000. Ship binman's SPI image instead, as rockpi-4a does.
function post_family_config__rockpi4c_uboot() {
	display_alert "$BOARD" "u-boot: binman SPI image, TF-A lts-v2.14.11" "info"
	declare -g UBOOT_TARGET_MAP="BL31=bl31.elf ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin"
	unset uboot_custom_postprocess
	declare -g ATFSOURCE="https://git.trustedfirmware.org/TF-A/trusted-firmware-a.git"
	declare -g ATFBRANCH="tag:lts-v2.14.11"
	declare -g ATFPATCHDIR="atf-rockchip64/v2.14"
}

function post_config_uboot_target__rockpi4c_features() {
	display_alert "$BOARD" "u-boot: enable network boot, storage and debug commands" "info"
	local opt
	for opt in CMD_DHCP CMD_PING CMD_PXE CMD_TFTPBOOT CMD_NFS CMD_WGET CMD_DNS \
		ROCKCHIP_EFUSE MISC_INIT_R \
		CMD_NVME CMD_SCSI CMD_SF CMD_MTD CMD_EXT4_WRITE FAT_WRITE \
		CMD_GPIO CMD_I2C CMD_PMIC CMD_REGULATOR CMD_LED CMD_POWEROFF \
		DM_RNG RNG_ROCKCHIP CMD_RNG CMD_KASLRSEED CMD_HASH CMD_BOOTMENU CMD_EFICONFIG; do
		run_host_command_logged scripts/config --enable "CONFIG_${opt}"
	done
}

function post_family_tweaks_bsp__rockpi-4c_BSP() {
	display_alert "Installing BSP firmware and fixups"

	if [[ $BRANCH == legacy ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

	fi

	return 0
}
