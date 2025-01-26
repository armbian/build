# Rockchip RK3399 hexa core 2G/4GB SoC GBe eMMC USB3 WiFi
BOARD_NAME="RockPro 64"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="joekhoobyar"
BOOTCONFIG="rockpro64-rk3399_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_SCENARIO="blobless"
BOOT_SUPPORT_SPI=yes

BOOTBRANCH_BOARD="tag:v2025.01"
BOOTPATCHDIR="v2025.01"

# Include fw_setenv, configured to point to the correct spot on the SPI Flash
PACKAGE_LIST_BOARD="libubootenv-tool" # libubootenv-tool provides fw_printenv and fw_setenv, for talking to U-Boot environment

function post_family_config__use_mainline_uboot_rockpro64() {
	# Do not set ATFBRANCH; instead uses the default from rockchip64_common, tested with v2.12.0 as of 2025.01[.09]

	display_alert "$BOARD" "using ATF (blobless) ${ATFBRANCH} for ${BOOTBRANCH_BOARD} u-boot" "info"
	# bl31.elf is copied directly from ATF build dir to uboot dir (by armbian u-boot build system)
	UBOOT_TARGET_MAP="BL31=bl31.elf;;u-boot-rockchip.bin u-boot-rockchip-spi.bin"

	# Ignore most of the rockchip64_common stuff, we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}

	function write_uboot_platform_mtd() {
		flashcp -v -p "$1/u-boot-rockchip-spi.bin" /dev/mtd0
	}
}
function post_config_uboot_target__extra_configs_for_rockpro64() {
	# Specific for rockpro64? CONFIG_OF_LIBFDT_OVERLAY=y should be generic
	display_alert "$BOARD" "u-boot configs for ${BOOTBRANCH_BOARD} u-boot config" "info"
	run_host_command_logged scripts/config --set-val CONFIG_OF_LIBFDT_OVERLAY "y"
	run_host_command_logged scripts/config --set-val CONFIG_MMC_HS400_SUPPORT "y"

	# upstream defconfig already has env in SPI: https://github.com/u-boot/u-boot/blob/v2025.01/configs/rockpro64-rk3399_defconfig

	display_alert "u-boot for ${BOARD}" "u-boot: enable EFI debugging command" "info"
	run_host_command_logged scripts/config --enable CMD_EFIDEBUG
	run_host_command_logged scripts/config --enable CMD_NVEDIT_EFI

	display_alert "u-boot for ${BOARD}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD

	display_alert "u-boot for ${BOARD}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO

	display_alert "u-boot for ${BOARD}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP_SACK

	# UMS, RockUSB, gadget stuff
	declare -a enable_configs=("CONFIG_CMD_USB_MASS_STORAGE" "CONFIG_USB_GADGET" "USB_GADGET_DOWNLOAD" "CONFIG_USB_FUNCTION_ROCKUSB" "CONFIG_USB_FUNCTION_ACM" "CONFIG_CMD_ROCKUSB" "CONFIG_CMD_USB_MASS_STORAGE")
	for config in "${enable_configs[@]}"; do
		display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable ${config}" "info"
		run_host_command_logged scripts/config --enable "${config}"
	done
	# Auto-enabled by the above, force off...
	run_host_command_logged scripts/config --disable USB_FUNCTION_FASTBOOT
}

function pre_config_uboot_target__rockpro64_patch_uboot_dtsi_for_ums() {
	display_alert "u-boot for ${BOARD}" "u-boot: add to u-boot dtsi for UMS" "info" # avoid a patch, just append to the dtsi file
	cat <<- UBOOT_BOARD_DTSI_OTG >> arch/arm/dts/rk3399-rockpro64-u-boot.dtsi
		&usbdrd_dwc3_0 { status = "okay"; dr_mode = "otg"; };
	UBOOT_BOARD_DTSI_OTG
}

# "rockchip-common: boot SD card first, then NVMe, then SATA, then USB, then mmc"
# On rockpro64, mmc0 is the eMMC, mmc1 is the SD card slot https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/rockchip/rk3399-rockpro64.dtsi#L15-L16
function pre_config_uboot_target__rockpro64_patch_rockchip_common_boot_order() {
	declare -a rockchip_uboot_targets=("mmc1" "nvme" "scsi" "usb" "mmc0" "pxe" "dhcp" "spi") # for future make-this-generic delight
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

function post_family_tweaks__config_rockpro64_fwenv() {
	display_alert "Configuring fw_printenv and fw_setenv" "for ${BOARD} and u-boot ${BOOTBRANCH_BOARD}" "info"
	# Addresses below come from CONFIG_ENV_OFFSET and CONFIG_ENV_SIZE in https://github.com/u-boot/u-boot/blob/v2024.07/configs/rockpro64-rk3399_defconfig
	cat <<- 'FW_ENV_CONFIG' > "${SDCARD}"/etc/fw_env.config
		# MTD on the SPI for the Rockpro64
		# MTD device name Device offset Env. size Flash sector size Number of sectors
		/dev/mtd0                       0x3F8000                      0x8000
	FW_ENV_CONFIG
}
