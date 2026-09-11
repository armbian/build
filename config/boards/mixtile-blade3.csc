# Rockchip RK3588 SoC octa core 16GB 4x PCIe Gen3 HDMI USB3 DP HDMIrx eMMC SD PD Mini-PCIe
declare -g BOARD_NAME="Mixtile Blade 3"
declare -g BOARD_VENDOR="mixtile"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOARD_MAINTAINER="rpardini"
declare -g INTRODUCED="2023"
declare -g KERNEL_TARGET="vendor,edge"
declare -g BOOT_FDT_FILE="rockchip/rk3588-blade3-v101-linux.dtb" # vendor DTB / mainline is changed below
declare -g BOOT_SCENARIO="tpl-blob-atf-mainline"
declare -g BOOT_SOC="rk3588"
declare -g BOOTCONFIG="mixtile-blade3-rk3588_defconfig" # mainline u-boot
declare -g IMAGE_PARTITION_TABLE="gpt"
declare -g UEFI_EDK2_BOARD_ID="blade3" # This _only_ used for uefi-edk2-rk3588 extension

enable_extension "uboot-mainline-mmc-env-storage" # store u-boot env in mmc (boot0/boot1)

function post_family_config__blade3_use_mainline_uboot() {
	display_alert "$BOARD" "mainline (next branch) u-boot overrides for $BOARD / $BRANCH" "info"
	declare -g BOOTDELAY=1

	BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.07"
	declare -g BOOTPATCHDIR="v2026.07" # with 000.patching_config.yaml - no patching, straight .dts/defconfigs et al

	BOOTDIR="u-boot-${BOARD}"

	UBOOT_TARGET_MAP="BL31=bl31.elf ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin" # NOT u-boot-rockchip-spi.bin
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd                # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}

	declare -g PLYMOUTH="no" # Disable plymouth as that only causes more confusion
}

function post_family_config__different_dtb_for_edge() {
	[[ "${BRANCH}" == *"edge" ]] || return 0 # only for edge/bleedingedge
	declare -g BOOT_FDT_FILE="rockchip/rk3588-mixtile-blade3.dtb"
	display_alert "$BOARD" "Using ${BOOT_FDT_FILE} for ${BRANCH}" "warn"
}

# "rockchip-common: boot SD card first, then NVMe, then mmc"
# include/configs/rockchip-common.h
# On the mixtile-blade3: mmc0 is eMMC; mmc1 is microSD
# Also the usb is non-functional in mainline u-boot right now, so we skip:  "scsi" "usb"
function pre_config_uboot_target__blade3_patch_rockchip_common_boot_order() {
	declare -a rockchip_uboot_targets=("mmc1" "nvme" "mmc0" "pxe" "dhcp" "spi") # for future make-this-generic delight
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

# Fancy up config
function post_config_uboot_target__mixtile_blade3_fancy_mainline_uboot_config() {
	display_alert "mainline u-boot" "Extra mainline u-boot configs for ${BOARD}/${BRANCH}" "info"

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

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable LWIP (new networking stack)" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_MII
	run_host_command_logged scripts/config --enable CONFIG_NET_LWIP

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable MBed TLS stuff" "info"
	run_host_command_logged scripts/config --enable CONFIG_WGET_HTTPS
	run_host_command_logged scripts/config --enable CONFIG_WGET_CACERT
	#run_host_command_logged scripts/config --enable CONFIG_WGET_BUILTIN_CACERT # not yet
	run_host_command_logged scripts/config --enable CONFIG_MBEDTLS_LIB

	# UMS, RockUSB, gadget stuff
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable UMS/RockUSB gadget" "info"
	declare -a enable_configs=("CONFIG_CMD_USB_MASS_STORAGE" "CONFIG_USB_GADGET" "USB_GADGET_DOWNLOAD" "CONFIG_USB_FUNCTION_ROCKUSB" "CONFIG_USB_FUNCTION_ACM" "CONFIG_CMD_ROCKUSB")
	for config in "${enable_configs[@]}"; do
		run_host_command_logged scripts/config --enable "${config}"
	done
	# Auto-enabled by the above, force off...
	run_host_command_logged scripts/config --disable USB_FUNCTION_FASTBOOT

	return 0
}
