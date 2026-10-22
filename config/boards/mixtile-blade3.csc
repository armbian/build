# Rockchip RK3588 SoC octa core 16GB 4x PCIe Gen3 HDMI USB3 DP HDMIrx eMMC SD PD Mini-PCIe
declare -g BOARD_NAME="Mixtile Blade 3"
declare -g BOARD_VENDOR="mixtile"
declare -g BOARDFAMILY="rockchip-rk3588"
declare -g BOARD_MAINTAINER="rpardini"
declare -g INTRODUCED="2023"
declare -g KERNEL_TARGET="vendor,edge"
declare -g BOOT_FDT_FILE="rockchip/rk3588-mixtile-blade3.dtb" # same name vendor and edge
declare -g BOOT_SOC="rk3588" # vendor blade3_defconfig name has no SoC to derive it from
declare -g IMAGE_PARTITION_TABLE="gpt"
declare -g UEFI_EDK2_BOARD_ID="blade3" # This _only_ used for uefi-edk2-rk3588 extension

# vendor* gets vendor u-boot, unless BLADE3_USE_MAINLINE_UBOOT=yes
# others get mainline u-boot, unless BLADE3_USE_VENDOR_UBOOT=yes
declare -g BLADE3_UBOOT="mainline"
if [[ "${BRANCH}" == vendor* ]]; then
	[[ "${BLADE3_USE_MAINLINE_UBOOT:-"no"}" == "yes" ]] || BLADE3_UBOOT="vendor"
else
	[[ "${BLADE3_USE_VENDOR_UBOOT:-"no"}" != "yes" ]] || BLADE3_UBOOT="vendor"
fi

if [[ "${BLADE3_UBOOT}" == "vendor" ]]; then
	declare -g BOOT_SCENARIO="spl-blobs"
	declare -g BOOTCONFIG="blade3_defconfig" # vendor u-boot; there is also blade3_sata_defconfig available
else
	declare -g BOOT_SCENARIO="tpl-blob-atf-mainline"
	declare -g BOOTCONFIG="mixtile-blade3-rk3588_defconfig" # mainline u-boot
	enable_extension "uboot-mainline-mmc-env-storage"       # store u-boot env in mmc (boot0/boot1)
fi

# Vendor U-Boot; override the rockchip-rk3588 family's. Meko's stable MAC patch breaks with Radxa's next-dev-v2024.10+
function post_family_config__blade3_use_vendor_uboot() {
	[[ "${BLADE3_UBOOT}" == "vendor" ]] || return 0
	display_alert "${BOARD}/${BRANCH}" "Using vendor U-Boot (Radxa next-dev-v2024.03) for ${BOARD}/${BRANCH}" "info"

	declare -g BOOTDELAY=1 # build injects this into u-boot config. we can then get into UMS mode and avoid the whole rockusb/rkdeveloptool thing
	declare -g BOOTSOURCE='https://github.com/radxa/u-boot.git'
	declare -g BOOTBRANCH='branch:next-dev-v2024.03' # NOT next-dev-v2024.10
	declare -g BOOTPATCHDIR="legacy/u-boot-radxa-rk35xx"
}

# Mainline U-Boot
function post_family_config__blade3_use_mainline_uboot() {
	[[ "${BLADE3_UBOOT}" == "mainline" ]] || return 0
	display_alert "${BOARD}/${BRANCH}" "Using mainline U-Boot for ${BOARD}/${BRANCH}" "info"

	# If BRANCH==vendor, use rkbin BL31 ${RKBIN_DIR}/${BL31_BLOB}, otherwise, bl31.elf from mainline ATF/TF-A
	declare bl31_blob="undetermined"
	if [[ "${BRANCH}" == vendor* ]]; then
		display_alert "${BOARD}/${BRANCH}" "Using Rockchip rkbin BL31 blob : ${RKBIN_DIR}/${BL31_BLOB}" "info"
		bl31_blob="${RKBIN_DIR}/${BL31_BLOB}"
		declare -g ATF_COMPILE="no" # no need to build mainline it either
	else
		display_alert "${BOARD}/${BRANCH}" "Using mainline BL31: bl31.elf from mainline ATF/TF-A" "info"
		bl31_blob="bl31.elf"
	fi

	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.10"
	declare -g BOOTPATCHDIR="v2026.10"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g UBOOT_TARGET_MAP="BL31=${bl31_blob} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # Disable stuff from rockchip64_common; we're using binman here which does all the work

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

# "rockchip-common: boot SD card first, then NVMe, then mmc"
# include/configs/rockchip-common.h
# On the mixtile-blade3: mmc0 is eMMC; mmc1 is microSD
# Also the usb is non-functional in mainline u-boot right now, so we skip:  "scsi" "usb"
function pre_config_uboot_target__blade3_patch_rockchip_common_boot_order() {
	[[ "${BLADE3_UBOOT}" == "mainline" ]] || return 0
	declare -a rockchip_uboot_targets=("mmc1" "nvme" "mmc0" "pxe" "dhcp" "spi") # for future make-this-generic delight
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

# Fancy up config
function post_config_uboot_target__mixtile_blade3_fancy_mainline_uboot_config() {
	[[ "${BLADE3_UBOOT}" == "mainline" ]] || return 0
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
