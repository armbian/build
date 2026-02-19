# Rockchip RK3588 SoC octa core 4-16GB SoC 2x1GBe eMMC USB3 NVMe SATA WiFi/BT HDMI DP HDMI-In RS232 RS485 LCD RotaryEncoder
declare -g BOARD_NAME="Mekotronics R58X-Pro"
declare -g BOARD_VENDOR="mekotronics"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOARD_MAINTAINER=""
declare -g KERNEL_TARGET="edge,vendor"
declare -g BOOT_FDT_FILE="rockchip/rk3588-mekotronics-r58x-pro.dtb" # mainline name; see below for vendor
declare -g DISPLAY_MANAGER="wayland"
declare -g ASOUND_STATE="asound.state.rk3588hd"
declare -g BOOT_SOC="rk3588"
declare -g IMAGE_PARTITION_TABLE="gpt"
# Does not have a UEFI_EDK2_BOARD_ID

if [[ "${BRANCH}" == "vendor" || "${BRANCH}" == "legacy" ]]; then
	display_alert "$BOARD" "vendor/legacy configuration applied for $BOARD / $BRANCH" "info"
	declare -g BOOTCONFIG="mekotronics_r58x-rk3588_defconfig"                       # vendor u-boot; with NVMe and a DTS
	declare -g BOOT_FDT_FILE="rockchip/rk3588-blueberry-edge-v12-maizhuo-linux.dtb" # different for vendor
	# Source shared vendor configuration; it does BOOT_SCENARIO="spl-blobs" & hciattach - common to all vendor-kernel Meko's
	source "${SRC}/config/sources/vendors/mekotronics/mekotronics-rk3588.conf.sh"
	return 0 # this returns early so below code is only for current/edge branches
fi

# For current/edge branches:
display_alert "$BOARD" "applying mainline configuration for $BOARD / $BRANCH" "info"
declare -g BOOT_SCENARIO="tpl-blob-atf-mainline" # Mainline ATF

function post_family_config__meko_r58x_pro_use_mainline_uboot() {
	display_alert "$BOARD" "mainline u-boot overrides for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="mekotronics-r58x-pro-rk3588_defconfig" # mainline
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.04-rc2"
	declare -g BOOTPATCHDIR="v2026.04"
	declare -g BOOTDIR="u-boot-${BOARD}"

	declare -g UBOOT_TARGET_MAP="BL31=bl31.elf ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}

	declare -g PLYMOUTH="no" # Disable plymouth as that only causes more confusion
}

# "rockchip-common: boot NVMe, SATA, USB, then eMMC last before PXE"
# include/configs/rockchip-common.h
# On the meko r58x_pro: mmc0 is eMMC; there is no SDcard reader @TODO yes there is
# Enumerating usb is pretty slow so do it after nvme
function pre_config_uboot_target__meko_r58x_pro_patch_rockchip_common_boot_order() {
	declare -a rockchip_uboot_targets=("nvme" "scsi" "usb" "mmc0" "pxe" "dhcp" "spi") # for future make-this-generic delight
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

function pre_config_uboot_target__meko_r58x_pro_patch_uboot_dtsi_for_ums() {
	[[ "${BRANCH}" == "vendor" ]] && return 0 # Not for 'vendor' branch, which uses 2017.09 vendor u-boot from Radxa

	display_alert "u-boot for ${BOARD}" "u-boot: add to u-boot dtsi for UMS" "info" # avoid a patch, just append to the dtsi file
	# Append to the t6 u-boot dtsi file with stuff for enabling gadget/otg/peripheral mode
	cat <<- EOD >> arch/arm/dts/rk3588-mekotronics-r58x-pro-u-boot.dtsi
		#include "rk3588-generic-u-boot.dtsi"
		&u2phy0 { status = "okay"; };
		&u2phy0_otg { status = "okay"; };
		&usbdp_phy0 { status = "okay"; };
		&usb_host0_xhci { dr_mode = "peripheral";  maximum-speed = "high-speed";  status = "okay"; };
	EOD
}

function post_config_uboot_target__extra_configs_for_meko_r58x_pro_mainline_environment_in_spi() {
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable board-specific configs" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_MISC

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable preboot & flash user LED in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'led 4G on; sleep 0.1; led LAN on; sleep 0.1; led PWR on; sleep 0.1; led 4G off; sleep 0.1; led LAN off; sleep 0.1;'" # double quotes required due to run_host_command_logged's quirks

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
