# Rockchip RK3566 quad core 4GB-8GB GBE PCIe USB3
BOARD_NAME="Pine Quartz64 A"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
BOOT_SOC="rk3566"
BOOTCONFIG="quartz64-a-rk3566_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3566-quartz64-a.dtb"
IMAGE_PARTITION_TABLE="gpt"

# Mainline U-Boot
function post_family_config__quartz64_a_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git" # We ❤️ Mainline U-Boot
	declare -g BOOTBRANCH="tag:v2025.04"
	declare -g BOOTPATCHDIR="v2025.04"
	declare -g BOOTDELAY=1 # Wait for UART interrupt to enter UMS/RockUSB mode etc

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable stuff from rockchip64_common; we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

# Quartz64a's OTG port is the BLACK one, on top of the USB3 port. Use an USB-A cable; not all cables work.
function pre_config_uboot_target__quartz64a_patch_uboot_dtsi_for_ums() {
	display_alert "u-boot for ${BOARD}" "u-boot: add to u-boot dtsi for UMS" "info" # avoid a patch, just append to the dtsi file
	cat <<- UBOOT_BOARD_DTSI_OTG >> arch/arm/dts/rk3566-quartz64-a-u-boot.dtsi
		&usb_host0_xhci { dr_mode = "otg"; };
	UBOOT_BOARD_DTSI_OTG
}

# "rockchip-common: boot SD card first, then NVMe, then SATA, then USB, then mmc"
# On quartz64a, mmc0 is the eMMC, mmc1 is the SD card slot
function pre_config_uboot_target__quartz64a_patch_rockchip_common_boot_order() {
	declare -a rockchip_uboot_targets=("mmc1" "nvme" "scsi" "usb" "mmc0" "pxe" "dhcp" "spi") # for future make-this-generic delight
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

# A better equivalent to patching a defconfig, do changes to .config via code.
# For UMS/RockUSB to work in u-boot, &usb_host0_xhci { dr_mode = "otg" } is required. See 0002-board-rockchip-ODROID-M1-override-kernel-DT-for-xhci-otg-dr_mode.patch
function post_config_uboot_target__extra_configs_for_quartz64a() {
	[[ "${BRANCH}" == "edge" || "${BRANCH}" == "current" ]] || return 0

	display_alert "u-boot for ${BOARD}" "u-boot: enable preboot & flash leds in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'echo armbian leds; led diy-led on; led work-led on; sleep 0.1; led diy-led off; led work-led off; sleep 0.1; led diy-led on;'" # double quote

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

	display_alert "u-boot for ${BOARD}" "u-boot: enable more cmdline commands" "info" # for extra compat with eg HAOS
	run_host_command_logged scripts/config --enable CONFIG_CMD_SQUASHFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_SETEXPR
	run_host_command_logged scripts/config --enable CONFIG_CMD_FILEENV # added via cmd-fileenv-read-string-from-file-into-env.patch
	run_host_command_logged scripts/config --enable CONFIG_CMD_CAT
	run_host_command_logged scripts/config --enable CONFIG_CMD_XXD

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enabling UMS/RockUSB Gadget functionality" "info"
	declare -a enable_configs=("CONFIG_CMD_USB_MASS_STORAGE" "CONFIG_USB_GADGET" "USB_GADGET_DOWNLOAD" "CONFIG_USB_FUNCTION_ROCKUSB" "CONFIG_USB_FUNCTION_ACM" "CONFIG_CMD_ROCKUSB" "CONFIG_CMD_USB_MASS_STORAGE")
	for config in "${enable_configs[@]}"; do
		run_host_command_logged scripts/config --enable "${config}"
	done
	# Auto-enabled by the above, force off...
	run_host_command_logged scripts/config --disable USB_FUNCTION_FASTBOOT
}
