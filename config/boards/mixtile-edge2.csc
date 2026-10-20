# Rockchip RK3568 quad core 4GB-8GB GBE PCIe USB3 SATA NVMe
BOARD_NAME="Mixtile Edge 2"
BOARD_VENDOR="mixtile"
BOARDFAMILY="rk35xx"
BOOTCONFIG="mixtile-edge2-rk3568_defconfig"
BOARD_MAINTAINER=""
INTRODUCED="2024"
KERNEL_TARGET="current,edge,vendor"
BOOT_FDT_FILE="rockchip/rk3568-mixtile-edge2.dtb"
OVERLAY_PREFIX_BOARD="mixtile-edge2"
IMAGE_PARTITION_TABLE="gpt"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
SRC_CMDLINE="earlycon=uart8250,mmio32,0xfe660000 loglevel=7 console=ttyS2,1500000" # for extlinux / EXT=u-boot-menu

if [[ "${BRANCH}" != vendor* ]]; then
	# mainline u-boot can store environment in eMMC (mmc0: boot0/boot1)
	enable_extension "uboot-mainline-mmc-env-storage"
fi

# Mainline U-Boot
function post_family_config__mixtile_edge2_use_mainline_uboot() {
	if [[ "${BRANCH}" == vendor* ]]; then
		display_alert "$BOARD" "Using vendor U-Boot for $BOARD / $BRANCH" "info"
		return
	fi

	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTDELAY=1
	declare -g BOOTCONFIG="mixtile-edge2-rk3568_defconfig"
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.10"
	declare -g BOOTPATCHDIR="v2026.10"
	declare -g BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable stuff from rockchip64_common; we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

function post_config_uboot_target__extra_configs_for_mixtile_edge2_uboot() {
	[[ "${BRANCH}" == vendor* ]] && return 0

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable preboot & flash user LED in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'led blue:status on; sleep 0.1; led blue:status off'" # double quotes required due to run_host_command_logged's quirks

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
