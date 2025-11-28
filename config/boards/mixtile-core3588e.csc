# Rockchip RK3588 SoC octa core Jetson SoM
declare -g BOARD_NAME="Mixtile Core3588E"
declare -g BOARD_VENDOR="mixtile"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOARD_MAINTAINER="rpardini"
declare -g KERNEL_TARGET="edge,vendor"
declare -g BOOT_FDT_FILE="rockchip/rk3588-mixtile-core3588e.dtb" # same name vendor and edge
declare -g BOOT_SCENARIO="spl-blobs"
declare -g BOOT_SOC="rk3588"
declare -g BOOTCONFIG="mixtile-core3588e-rk3588_defconfig" # edge/mainline
declare -g IMAGE_PARTITION_TABLE="gpt"
# Does NOT have a UEFI_EDK2_BOARD_ID

# Vendor kernel:
# - https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr5.1/arch/arm64/boot/dts/rockchip/rk3588-mixtile-core3588e.dts
#   - mostly works, still sucks as it's vendor kernel
#   - mainline u-boot can boot the vendor kernel just fine
# Mainline kernel:
# - https://github.com/Joshua-Riek/linux/blob/v6.7-rk3588/arch/arm64/boot/dts/rockchip/rk3588-mixtile-core3588e.dts
#   - a _lot_ of fixes and additions done on top; gpu/npu/i2c/thermals/etc

# Hardware notes:
# - With the LEETOP carrier board (as shipped by Mixtile)
#   - Recovery "button" (NOT real "Maskrom"): "jumper cap to connect the FCREC and GND pins"; this depends on u-boot actually working (not bricked)
#   - OTG/Maskrom port is micro-USB port
#   - The "real" maskrom is to short two tiny solder-joints near the SoC on the SoM; see https://dh19rycdk230a.cloudfront.net/app/uploads/2023/11/solder-joints.png
# - Pinout of the LEETOP carrier board: https://www.cnx-software.com/wp-content/uploads/2023/12/Leetop-A206-40-pin-GPIO-header-pintout.png
#   - pin 1 is 3.3v; pin 6 and 9 and 25 are GND;
#   - pin 3 is SDA; pin 5 is SCL --> i2c-5 confirmed (mainline kernel) // i2c-1 confirmed (vendor kernel)
#   - pin 27 is SDA; pin 28 is SCL --> unconfirmed
#   - pin 8 is UART TX; pin 10 is UART RX --> uart1 unconfirmed

function post_family_config__core3588e_use_mainline_uboot() {
	display_alert "$BOARD" "mainline u-boot overrides for $BOARD / $BRANCH" "info"

	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.01"
	declare -g BOOTPATCHDIR="v2026.01"
	declare -g BOOTDIR="u-boot-${BOARD}"

	UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}

	declare -g PLYMOUTH="no" # Disable plymouth as that only causes more confusion
}

# "rockchip-common: boot SD card first, then NVMe, then mmc"
# include/configs/rockchip-common.h
# On the mixtile-core3588e: mmc0 is eMMC; mmc1 is microSD (which doesn't really exist/work)
function pre_config_uboot_target__core3588e_patch_rockchip_common_boot_order() {
	declare -a rockchip_uboot_targets=("mmc1" "nvme" "scsi" "usb" "mmc0" "pxe" "dhcp" "spi") # for future make-this-generic delight
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

function post_config_uboot_target__extra_configs_for_core3588e_mainline_environment_in_spi() {
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable board-specific configs" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_MISC

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable preboot & flash user LED in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'led sys_led on; sleep 0.1; led sys_led off'" # double quotes required due to run_host_command_logged's quirks

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable EFI debugging commands" "info"
	run_host_command_logged scripts/config --enable CMD_EFIDEBUG
	run_host_command_logged scripts/config --enable CMD_NVEDIT_EFI

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable more filesystems support" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_BTRFS

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP_SACK

	# UMS, RockUSB, gadget stuff
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable UMS/RockUSB gadget" "info"
	declare -a enable_configs=("CONFIG_CMD_USB_MASS_STORAGE" "CONFIG_USB_GADGET" "USB_GADGET_DOWNLOAD" "CONFIG_USB_FUNCTION_ROCKUSB" "CONFIG_USB_FUNCTION_ACM" "CONFIG_CMD_ROCKUSB" "CONFIG_CMD_USB_MASS_STORAGE")
	for config in "${enable_configs[@]}"; do
		run_host_command_logged scripts/config --enable "${config}"
	done
	# Auto-enabled by the above, force off...
	run_host_command_logged scripts/config --disable USB_FUNCTION_FASTBOOT
}
