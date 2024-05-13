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

# u-boot v2024.04-rc4 for rockpro64
BOOTBRANCH_BOARD="tag:v2024.04-rc4"
BOOTPATCHDIR="v2024.04"

# Include fw_setenv, configured to point to the correct spot on the SPI Flash
PACKAGE_LIST_BOARD="libubootenv-tool" # libubootenv-tool provides fw_printenv and fw_setenv, for talking to U-Boot environment

function post_family_config__use_mainline_uboot_rockpro64() {
	# Use latest lts 2.8 ATF
	ATFBRANCH='tag:lts-v2.8.16'
	ATFPATCHDIR="atf-rockchip64" # patches for logging etc
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

# From Kwiboo:
#  ... "note that u-boot mainline for rk3328/rk3399 suffers from a limitation in that the u-boot.bin may not exceed 1000 KiB or the stack may overwrite part of it during runtime, resulting in strange unexplained issues.
#       This has been fixed in current U-Boot next branch with https://github.com/u-boot/u-boot/commit/5e7cd8a119953dc2f466fea81e230d683ee03493 and should be included with v2024.07-rc1
#       If your u-boot.bin build output is less than 950 KiB in size you should not suffer from this limitation/issue."
#  ... "The real limit will be at most 1 MiB - 16 KiB (malloc heap on stack) = 1008 KiB and any additional runtime usage of the stack will take up until U-Boot has been relocated to top of RAM,
#       lets say an additional 16 KiB (same as malloc heap) to be on the safer side, so I would suggest you check for e.g. < 992 KiB or similar instead of < 1 MiB.
#       As long as the generated u-boot.bin is < 992 KiB I think it should be safe, and I do not think the stack usage will be that much before relocation so < 1000 KiB may also be fine 😎"
# rpardini: close call; the u-boot.bin is 994920 bytes. Let's check for >992KiB and break the build if it's too large.
function post_uboot_custom_postprocess__check_bin_size_less_than_992KiB() {
	declare one_bin
	declare -i uboot_bin_size
	declare -a bins_to_check=("u-boot.bin")
	for one_bin in "${bins_to_check[@]}"; do
		uboot_bin_size=$(stat -c %s "${one_bin}")
		display_alert "Checking u-boot ${BOARD} bin size" "'${one_bin}' is less than 992KiB (1015808 bytes): ${uboot_bin_size} bytes" "info"
		if [[ ${uboot_bin_size} -ge 1015808 ]]; then
			display_alert "u-boot for ${BOARD}" "'${one_bin}' is larger than 992KiB (1015808 bytes): ${uboot_bin_size} bytes" "err"
			exit_with_error "u-boot ${BOARD} bin size check failed"
		fi
	done
}

function post_config_uboot_target__extra_configs_for_rockpro64() {
	# Taken from https://gitlab.manjaro.org/manjaro-arm/packages/core/uboot-rockpro64/-/blob/master/PKGBUILD
	display_alert "$BOARD" "u-boot configs for ${BOOTBRANCH_BOARD} u-boot config" "info"
	run_host_command_logged scripts/config --set-val CONFIG_OF_LIBFDT_OVERLAY "y"
	run_host_command_logged scripts/config --set-val CONFIG_MMC_HS400_SUPPORT "y"
	run_host_command_logged scripts/config --set-val CONFIG_USE_PREBOOT "n"
}

function post_family_tweaks__config_rockpro64_fwenv() {
	display_alert "Configuring fw_printenv and fw_setenv" "for ${BOARD} and u-boot ${BOOTBRANCH_BOARD}" "info"
	# Addresses below come from CONFIG_ENV_OFFSET and CONFIG_ENV_SIZE in https://github.com/u-boot/u-boot/blob/v2024.04-rc4/configs/rockpro64-rk3399_defconfig
	cat <<- 'FW_ENV_CONFIG' > "${SDCARD}"/etc/fw_env.config
		# MTD on the SPI for the Rockpro64
		# MTD device name Device offset Env. size Flash sector size Number of sectors
		/dev/mtd0                       0x3F8000                      0x8000
	FW_ENV_CONFIG
}
